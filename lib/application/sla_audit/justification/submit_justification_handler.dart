import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
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
/// - **Operator/Admin path**: [callerRole] must have [UserPermission.canSubmitJustification].
/// - **Token path**: [callerRole] is null and [submittedByTokenId] is non-null
///   (driver self-service via tokenised link â€” PO-1).
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

  Future<ContractorJustification> handle(
    SubmitJustificationCommand command,
  ) async {
    // â”€â”€ Step 1: INV-1 Fail-Fast Identity Sync â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC â€” token path (null role) bypasses permission check (PO-1)
    final isTokenPath =
        command.callerRole == null && command.submittedByTokenId != null;
    final role = command.callerRole;
    if (!isTokenPath &&
        (role == null ||
            !_rbac.can(role, UserPermission.canSubmitJustification))) {
      throw const DomainException('Unauthorized.');
    }

    // 2. Validate category â€” throws ArgumentError converted to DomainException
    final JustificationCategory category;
    try {
      category = JustificationCategory.fromDb(command.category);
    } on ArgumentError {
      throw DomainException(
        'Invalid justification category: ${command.category}',
      );
    }

    // 3. Validate description length (PO-3)
    if (command.description.trim().length < 20) {
      throw const DomainException(
        'Description must be at least 20 characters.',
      );
    }

    // 4. INV-9: Evidence is mandatory for forensic defensibility
    if (command.evidenceHashes.isEmpty) {
      throw const DomainException(
        'Evidence required: At least one cryptographic hash must be provided.',
      );
    }

    // 4.1 Server-authoritative forensic throttle (INV-16, INV-18).
    // A modified client cannot bypass the backoff horizon — the RPC enforces
    // JWT-claim tenancy and persists state under RLS.
    await _throttle.assertAllowed(organizationId: command.organizationId);

    // 4.2 Two-pass contextual scan of uploaded evidence (INV-9, INV-13).
    // Failure surface: increment server-side throttle, then rethrow so the UI
    // can render the precise ForensicViolationException verdict.
    try {
      await _analyzer.validateEvidence(command.evidenceUrls);
    } on ForensicViolationException {
      await _throttle.recordFailure(organizationId: command.organizationId);
      rethrow;
    }
    await _throttle.recordSuccess(organizationId: command.organizationId);

    final now = _clock.nowUtc();
    final id = const Uuid().v4();
    final actorUserId = command.callerUserId ?? 'TOKEN';

    // 4. Persist justification
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

    // 5. Persist evidence uploads (INV-8)
    for (final hash in command.evidenceHashes) {
      await _justificationRepo.addEvidence(
        JustificationEvidence(
          id: const Uuid().v4(),
          justificationId: id,
          organizationId: command.organizationId,
          fileName: hash, // filename resolved UI-side; hash is the identity key
          contentHash: hash,
          storagePath: '',
          uploadedAtUtc: now,
        ),
      );
    }

    // 6. Build domain event
    final event = JustificationSubmittedEvent(
      organizationId: command.organizationId,
      occurredAtUtc: now,
      justificationId: id,
      setId: command.setId,
      contractId: command.contractId,
      planVersion: command.planVersion,
      actorUserId: actorUserId,
      evidenceHashes: command.evidenceHashes,
    );

    // 7. Append JUSTIFICATION_SUBMITTED to immutable ledger (INV-7)
    await _ledger.append(SlaLedgerMapper.mapToEntry(event));

    // 8. Enqueue PendingFact for offline resilience (INV-11 idempotency)
    final factId = _deterministicFactId(
      command.contractId,
      command.setId,
      actorUserId,
    );
    final payloadJson = jsonEncode({
      'type': 'JUSTIFICATION_SUBMITTED',
      'justificationId': id,
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

    return justification;
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
