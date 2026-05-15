import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';
import 'package:veraprob/domain/sla_audit/justification/contractor_justification.dart';
import 'package:veraprob/domain/sla_audit/justification/forensic_throttle_gateway.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_category.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_evidence.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_repository.dart';
import 'package:veraprob/domain/sla_audit/justification/justification_status.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/local_fact_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/pending_fact.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/sync_status.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'submit_justification_command.dart';
import 'package:veraprob/application/sla_audit/sla_ledger_mapper.dart';

/// Application handler for [SubmitJustificationCommand].
///
/// Two authorisation paths:
/// - **Operator/Admin path**: [SubmitJustificationCommand.callerRole] must have
///   [UserPermission.canSubmitJustification].
/// - **Token path**: [SubmitJustificationCommand.callerRole] is null and
///   [SubmitJustificationCommand.submittedByTokenId] is non-null (driver
///   self-service via tokenised link — PO-1).
///
/// Idempotency (INV-11): deterministic [PendingFact.factId] derived from
/// contractId + setId + actorUserId prevents duplicate enqueue on retry.
class SubmitJustificationHandler {
  final TenantValidationService _tenantValidator;
  final JustificationRepository _justificationRepo;
  final SlaAuditLedgerRepository _ledger;
  final LocalFactQueueRepository _factQueue;
  final RbacService _rbac;
  final IDateTimeProvider _clock;
  final ContextualSignatureAnalyzer _analyzer;
  final ForensicThrottleGateway _throttle;

  SubmitJustificationHandler({
    required TenantValidationService tenantValidator,
    required JustificationRepository justificationRepo,
    required SlaAuditLedgerRepository ledger,
    required LocalFactQueueRepository factQueue,
    required RbacService rbac,
    required IDateTimeProvider clock,
    required ContextualSignatureAnalyzer analyzer,
    required ForensicThrottleGateway throttle,
  }) : _tenantValidator = tenantValidator,
       _justificationRepo = justificationRepo,
       _ledger = ledger,
       _factQueue = factQueue,
       _rbac = rbac,
       _clock = clock,
       _analyzer = analyzer,
       _throttle = throttle;

  /// Orchestrates justification submission. Each step is an atomic private
  /// method; ordering of side-effecting awaits is forensically significant
  /// (INV-7, INV-15, INV-18) and must not be reordered.
  Future<ContractorJustification> handle(
    SubmitJustificationCommand command,
  ) async {
    // INV-1: Fail-Fast identity sync — must remain the first call.
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    _authorize(command);
    final category = _parseCategory(command);
    _assertCommandValid(command);
    await _scanEvidence(command);

    // Deterministic snapshot — computed once, threaded through every step
    // so replay is byte-identical (INV-15).
    final now = _clock.nowUtc();
    final id = const Uuid().v4();
    final actorUserId = command.callerUserId ?? 'TOKEN';

    final justification = await _persistJustification(
      command,
      category,
      id,
      now,
    );
    await _persistEvidence(command, id, now);
    await _appendLedger(command, id, now, actorUserId);
    await _enqueueFact(command, id, now, actorUserId);

    return justification;
  }

  /// RBAC gate. The token path (null role + non-null token) is a deliberate
  /// permission bypass for driver self-service (PO-1); every other caller
  /// must hold [UserPermission.canSubmitJustification].
  void _authorize(SubmitJustificationCommand command) {
    final isTokenPath =
        command.callerRole == null && command.submittedByTokenId != null;
    if (isTokenPath) return;

    final role = command.callerRole;
    if (role == null ||
        !_rbac.can(role, UserPermission.canSubmitJustification)) {
      throw const DomainException('Unauthorized.');
    }
  }

  /// Parses the raw category string, translating the infrastructure-level
  /// [ArgumentError] into a domain [DomainException] so the presentation
  /// layer sees one consistent error type.
  JustificationCategory _parseCategory(SubmitJustificationCommand command) {
    try {
      return JustificationCategory.fromDb(command.category);
    } on ArgumentError {
      throw DomainException(
        'Invalid justification category: ${command.category}',
      );
    }
  }

  /// Input invariants: minimum description length (PO-3) and mandatory
  /// cryptographic evidence (INV-9 — forensic defensibility).
  void _assertCommandValid(SubmitJustificationCommand command) {
    if (command.description.trim().length < 20) {
      throw const DomainException(
        'Description must be at least 20 characters.',
      );
    }
    if (command.evidenceHashes.isEmpty) {
      throw const DomainException(
        'Evidence required: At least one cryptographic hash must be provided.',
      );
    }
  }

  /// Server-authoritative evidence gate (INV-16, INV-18). Order is critical:
  /// throttle horizon is asserted first, then the two-pass contextual scan;
  /// a [ForensicViolationException] increments the server-side throttle
  /// before rethrowing so the UI renders the precise verdict. A clean scan
  /// records success.
  Future<void> _scanEvidence(SubmitJustificationCommand command) async {
    await _throttle.assertAllowed(organizationId: command.organizationId);
    try {
      await _analyzer.validateEvidence(command.evidenceUrls);
    } on ForensicViolationException {
      await _throttle.recordFailure(organizationId: command.organizationId);
      rethrow;
    }
    await _throttle.recordSuccess(organizationId: command.organizationId);
  }

  /// Persists the justification aggregate root (INV-8: org-scoped write).
  Future<ContractorJustification> _persistJustification(
    SubmitJustificationCommand command,
    JustificationCategory category,
    String id,
    DateTime now,
  ) async {
    final justification = ContractorJustification(
      id: id,
      organizationId: command.organizationId,
      contractId: command.contractId,
      setId: command.setId,
      submittedByToken: command.submittedByTokenId,
      category: category,
      description: command.description,
      status: JustificationStatus.pending,
      reviewedByUserId: null,
      reviewedAtUtc: null,
      createdAtUtc: now,
    );
    await _justificationRepo.create(justification);
    return justification;
  }

  /// Persists each uploaded evidence record, sealed by its content hash
  /// (INV-8). The hash doubles as the identity key; filename is resolved
  /// UI-side.
  Future<void> _persistEvidence(
    SubmitJustificationCommand command,
    String justificationId,
    DateTime now,
  ) async {
    for (final hash in command.evidenceHashes) {
      await _justificationRepo.addEvidence(
        JustificationEvidence(
          id: const Uuid().v4(),
          justificationId: justificationId,
          organizationId: command.organizationId,
          fileName: hash,
          contentHash: hash,
          storagePath: '',
          uploadedAtUtc: now,
        ),
      );
    }
  }

  /// Appends `JUSTIFICATION_SUBMITTED` to the immutable ledger (INV-7).
  Future<void> _appendLedger(
    SubmitJustificationCommand command,
    String justificationId,
    DateTime now,
    String actorUserId,
  ) async {
    final event = JustificationSubmittedEvent(
      organizationId: command.organizationId,
      occurredAtUtc: now,
      justificationId: justificationId,
      setId: command.setId,
      contractId: command.contractId,
      planVersion: command.planVersion,
      actorUserId: actorUserId,
      evidenceHashes: command.evidenceHashes,
    );
    await _ledger.append(SlaLedgerMapper.mapToEntry(event));
  }

  /// Enqueues a [PendingFact] for offline resilience. The deterministic
  /// [factId] guarantees a retry does not duplicate the queue entry (INV-11).
  Future<void> _enqueueFact(
    SubmitJustificationCommand command,
    String justificationId,
    DateTime now,
    String actorUserId,
  ) async {
    final factId = _deterministicFactId(
      command.contractId,
      command.setId,
      actorUserId,
    );
    final payloadJson = jsonEncode({
      'type': 'JUSTIFICATION_SUBMITTED',
      'justificationId': justificationId,
      'contractId': command.contractId,
      'setId': command.setId,
      'organizationId': command.organizationId,
    });
    final contentHash = sha256.convert(utf8.encode(payloadJson)).toString();
    await _factQueue.enqueue(
      PendingFact.reconstitute(
        factId: factId,
        organizationId: command.organizationId,
        contentHash: contentHash,
        factPayloadJson: payloadJson,
        receivedAtUtc: now,
        queuedAtUtc: now,
        syncStatus: SyncStatus.pending,
        localSequence: 0,
        retryCount: 0,
      ),
    );
  }

  /// Deterministic UUID derived from contractId + setId + actorUserId.
  /// Guarantees idempotency: re-submitting the same justification does not
  /// duplicate the PendingFact queue entry (INV-11).
  static String _deterministicFactId(
    String contractId,
    String setId,
    String actorUserId,
  ) {
    final seed = '$contractId|$setId|$actorUserId';
    final bytes = utf8.encode(seed);
    final hash = sha256.convert(bytes).toString();
    // Format first 32 hex chars as UUID v5-style (deterministic, no collision)
    return '${hash.substring(0, 8)}-${hash.substring(8, 12)}-'
        '${hash.substring(12, 16)}-${hash.substring(16, 20)}-'
        '${hash.substring(20, 32)}';
  }
}
