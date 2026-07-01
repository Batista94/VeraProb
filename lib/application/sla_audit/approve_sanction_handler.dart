import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'dart:async';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'package:veraprob/application/sla_audit/webhook_dispatcher_port.dart';
import 'approve_sanction_command.dart';

/// Application handler for [ApproveSanctionCommand].
///
/// Enforces Human-in-the-Loop: only this handler can generate a
/// `VERDICT_SEALED` ledger entry. The engine NEVER does this directly.
///
/// **Concurrency + atomicity (DB-enforced):** the write path is a single call to
/// [SanctionReviewCommandRepository.approveSanction], backed by the
/// `approve_sanction` SECURITY DEFINER RPC. The RPC row-locks the queue entry,
/// re-checks the `pending` status (closing the TOCTOU race where two auditors
/// appended duplicate `VERDICT_SEALED` facts), appends the verdict ledger fact
/// (INV-3), and flips the queue — all in ONE transaction. A concurrent loser
/// raises `IdempotencyProcessingException` from the RPC; no second fact is
/// appended.
///
/// The client-side checks below (tenant, RBAC, status) are retained as fail-fast
/// UX and anti-oracle guards; they are NOT the concurrency barrier — that is the
/// DB row lock.
class ApproveSanctionHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SanctionReviewCommandRepository _reviewRepo;
  final RbacService _rbac;
  final IDateTimeProvider _dateTimeProvider;
  final IWebhookDispatcherPort? _webhookDispatcher;

  ApproveSanctionHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SanctionReviewCommandRepository reviewRepo,
    required RbacService rbac,
    IDateTimeProvider? dateTimeProvider,
    IWebhookDispatcherPort? webhookDispatcher,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _reviewRepo = reviewRepo,
       _rbac = rbac,
       _dateTimeProvider = dateTimeProvider ?? BrazilDateTimeProvider(),
       _webhookDispatcher = webhookDispatcher;

  /// Handles the command by transitioning the queue entry to [applied]
  /// and appending a `VERDICT_SEALED` entry to the immutable ledger, atomically.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canApproveSanctions]
  /// - Queue entry not found for the given [organizationId]
  /// - Entry is not in [SanctionReviewStatus.pending] (idempotency fail-fast)
  Future<void> handle(ApproveSanctionCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check — before any I/O (prevents oracle attacks)
    if (!_rbac.can(command.callerRole, UserPermission.canApproveSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 3. Load queue entry — scoped to organizationId (tenant isolation, INV-1).
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

    // 4. Idempotency fail-fast: only pending entries can be approved.
    if (entry.status != SanctionReviewStatus.pending) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is already ${entry.status.name}.',
      );
    }

    // 5. Atomic write (lock → re-check → ledger append → queue flip) in ONE DB
    //    transaction. Concurrency control + atomicity live here.
    await _reviewRepo.approveSanction(
      organizationId: command.organizationId,
      queueEntryId: command.queueEntryId,
      reviewedByUserId: command.approvedByUserId,
      actorEmail: command.actorEmail,
      occurredAtUtc: _dateTimeProvider.nowUtc(),
      reasonCode: command.reasonCode,
      reviewerReason: command.reviewerReason,
    );

    // 6. Fire and forget webhook dispatch (Phase 10.7)
    // Runs outside the atomic boundary; failure is reconciled by cron.
    final dispatcher = _webhookDispatcher;
    if (dispatcher != null) {
      unawaited(
        dispatcher.dispatchVerdictWebhooks(
          organizationId: command.organizationId,
        ),
      );
    }
  }
}
