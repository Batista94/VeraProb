import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'reject_sanction_command.dart';

/// Application handler for [RejectSanctionCommand].
///
/// Enforces Human-in-the-Loop with documented reason. A rejection with
/// `rejectionReason.trim().length < 10` is rejected at the application layer
/// to ensure forensic traceability of every negative verdict.
///
/// **Concurrency + atomicity (DB-enforced):** the write path is a single call to
/// [SanctionReviewCommandRepository.rejectSanction], backed by the
/// `reject_sanction` SECURITY DEFINER RPC (row lock → `pending` re-check →
/// `VERDICT_REFUSED` append → queue flip, in ONE transaction). A concurrent
/// loser raises `IdempotencyProcessingException`; no second fact is appended.
/// The client-side checks are fail-fast UX/anti-oracle guards, not the barrier.
class RejectSanctionHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SanctionReviewCommandRepository _reviewRepo;
  final RbacService _rbac;
  final IDateTimeProvider _clock;

  RejectSanctionHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SanctionReviewCommandRepository reviewRepo,
    required RbacService rbac,
    required IDateTimeProvider clock,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _reviewRepo = reviewRepo,
       _rbac = rbac,
       _clock = clock;

  /// Handles the command by transitioning the queue entry to [rejected]
  /// and appending a `VERDICT_REFUSED` entry to the immutable ledger, atomically.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canRejectSanctions]
  /// - [rejectionReason] is shorter than 10 characters after trimming
  /// - Queue entry not found for the given [organizationId]
  /// - Entry is not in [SanctionReviewStatus.pending] (idempotency fail-fast)
  Future<void> handle(RejectSanctionCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check — before any I/O (prevents oracle attacks)
    if (!_rbac.can(command.callerRole, UserPermission.canRejectSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 3. Validate rejection reason (forensic traceability requirement)
    if (command.rejectionReason.trim().length < 10) {
      throw const DomainException(
        'rejectionReason must be at least 10 characters.',
      );
    }

    // 4. Load queue entry — scoped to organizationId (tenant isolation, INV-1).
    //    Fail-fast UX guard only; the authoritative lock lives in the RPC.
    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    // 5. Idempotency fail-fast: only pending entries can be rejected.
    if (entry.status != SanctionReviewStatus.pending) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is already ${entry.status.name}.',
      );
    }

    // 6. Atomic write (lock → re-check → ledger append → queue flip) in ONE DB
    //    transaction. Concurrency control + atomicity live here.
    await _reviewRepo.rejectSanction(
      organizationId: command.organizationId,
      queueEntryId: command.queueEntryId,
      reviewedByUserId: command.rejectedByUserId,
      actorEmail: command.actorEmail,
      rejectionReason: command.rejectionReason.trim(),
      occurredAtUtc: _clock.nowUtc(),
    );
  }
}
