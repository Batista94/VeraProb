import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'approve_sanction_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [ApproveSanctionCommand].
///
/// Enforces Human-in-the-Loop: only this handler can generate a
/// `VERDICT_SEALED` ledger entry. The engine NEVER does this directly.
///
/// Contains NO domain logic â€” authorization and idempotency guards are
/// application-layer concerns. Ledger append is irreversible (INV-1).
class ApproveSanctionHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;
  final IDateTimeProvider _dateTimeProvider;

  ApproveSanctionHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
    IDateTimeProvider? dateTimeProvider,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _ledger = ledger,
       _rbac = rbac,
       _dateTimeProvider = dateTimeProvider ?? BrazilDateTimeProvider();

  /// Handles the command by transitioning the queue entry to [applied]
  /// and appending a `VERDICT_SEALED` entry to the immutable ledger.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canApproveSanctions]
  /// - Queue entry not found for the given [organizationId]
  /// - Entry is not in [SanctionReviewStatus.pending] (idempotency guard, INV-24)
  Future<void> handle(ApproveSanctionCommand command) async {
    // â”€â”€ Step 1: INV-1 Fail-Fast Identity Sync â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check â€” before any I/O (prevents oracle attacks)
    if (!_rbac.can(command.callerRole, UserPermission.canApproveSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 2. Load queue entry â€” scoped to organizationId (tenant isolation, INV-6)
    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    // 3. Idempotency guard (INV-24): only pending entries can be approved
    if (entry.status != SanctionReviewStatus.pending) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is already ${entry.status.name}.',
      );
    }

    final now = _dateTimeProvider.nowUtc();

    // 4. Build domain event carrying VerdictEvidence forward
    final event = SanctionAppliedEvent(
      organizationId: entry.organizationId,
      occurredAtUtc: now,
      setId: entry.setId,
      contractId: entry.contractId,
      planVersion: 0, // planVersion is not carried in the queue entry
      queueEntryId: entry.id,
      approvedByUserId: command.approvedByUserId,
      actorEmail: command.actorEmail,
      verdictEvidence: entry.verdictEvidence,
    );

    // 5. Append VERDICT_SEALED to the immutable ledger (INV-1, Pillar C)
    await _ledger.append(SlaLedgerMapper.mapToEntry(event));

    // 6. Update queue entry status to applied
    final updated = entry.copyWith(
      status: SanctionReviewStatus.applied,
      reviewedAtUtc: now,
      reviewedByUserId: command.approvedByUserId,
    );
    await _queueRepo.updateStatus(updated);
  }
}
