import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/execution_events.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'reject_sanction_command.dart';
import 'sla_ledger_mapper.dart';

/// Application handler for [RejectSanctionCommand].
///
/// Enforces Human-in-the-Loop with documented reason. A rejection with
/// `rejectionReason.trim().length < 10` is rejected at the application layer
/// to ensure forensic traceability of every negative verdict.
class RejectSanctionHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SlaAuditLedgerRepository _ledger;
  final RbacService _rbac;
  final IDateTimeProvider _clock;

  RejectSanctionHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SlaAuditLedgerRepository ledger,
    required RbacService rbac,
    required IDateTimeProvider clock,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _ledger = ledger,
       _rbac = rbac,
       _clock = clock;

  /// Handles the command by transitioning the queue entry to [rejected]
  /// and appending a `VERDICT_REFUSED` entry to the immutable ledger.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canRejectSanctions]
  /// - Queue entry not found for the given [organizationId]
  /// - Entry is not in [SanctionReviewStatus.pending] (idempotency guard, INV-24)
  /// - [rejectionReason] is shorter than 10 characters after trimming
  Future<void> handle(RejectSanctionCommand command) async {
    // â”€â”€ Step 1: INV-1 Fail-Fast Identity Sync â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check â€” before any I/O (prevents oracle attacks)
    if (!_rbac.can(command.callerRole, UserPermission.canRejectSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 2. Validate rejection reason (forensic traceability requirement)
    if (command.rejectionReason.trim().length < 10) {
      throw const DomainException(
        'rejectionReason must be at least 10 characters.',
      );
    }

    // 3. Load queue entry â€” scoped to organizationId (tenant isolation, INV-6)
    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    // 4. Idempotency guard (INV-24): only pending entries can be rejected
    if (entry.status != SanctionReviewStatus.pending) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is already ${entry.status.name}.',
      );
    }

    final now = _clock.nowUtc();

    // 5. Build domain event carrying VerdictEvidence and reason forward
    final event = SanctionRejectedEvent(
      organizationId: entry.organizationId,
      occurredAtUtc: now,
      setId: entry.setId,
      contractId: entry.contractId,
      planVersion: 0,
      queueEntryId: entry.id,
      rejectedByUserId: command.rejectedByUserId,
      actorEmail: command.actorEmail,
      rejectionReason: command.rejectionReason.trim(),
      verdictEvidence: entry.verdictEvidence,
    );

    // 6. Append VERDICT_REFUSED to the immutable ledger (INV-1, Pillar C)
    await _ledger.append(SlaLedgerMapper.mapToEntry(event));

    // 7. Update queue entry status to rejected
    final updated = entry.copyWith(
      status: SanctionReviewStatus.rejected,
      reviewedAtUtc: now,
      reviewedByUserId: command.rejectedByUserId,
      rejectionReason: command.rejectionReason.trim(),
    );
    await _queueRepo.updateStatus(updated);
  }
}
