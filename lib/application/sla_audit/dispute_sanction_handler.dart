import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'dispute_sanction_command.dart';

/// Application handler for [DisputeSanctionCommand].
///
/// Under the CIA Triad:
/// 1. **Confidentiality:** Scopes queue retrieval to [command.organizationId] and asserts tenant identity.
/// 2. **Integrity:** Enforces RBAC roles and prevents changing states of already finalized entries.
/// 3. **Availability:** Ensures predictable execution transitions.
///
/// **Concurrency + atomicity (DB-enforced):** the write path is a single call to
/// [SanctionReviewCommandRepository.disputeSanction], backed by the
/// `dispute_sanction` SECURITY DEFINER RPC. The RPC row-locks the queue entry,
/// re-checks the `pending` status (closing the TOCTOU race), appends the
/// `SANCTION_DISPUTED` ledger fact (INV-3), flips the queue, and seals the
/// dispute provenance (disputed_at/disputed_by/resolution_due_at) inline.
class DisputeSanctionHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SanctionReviewCommandRepository _reviewRepo;
  final RbacService _rbac;
  final IDateTimeProvider _dateTimeProvider;

  DisputeSanctionHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SanctionReviewCommandRepository reviewRepo,
    required RbacService rbac,
    IDateTimeProvider? dateTimeProvider,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _reviewRepo = reviewRepo,
       _rbac = rbac,
       _dateTimeProvider = dateTimeProvider ?? BrazilDateTimeProvider();

  /// Transitions a pending queue entry to `disputed` (Hold / Waiting for Evidence).
  /// Appends a `SANCTION_DISPUTED` entry to the immutable ledger for audit traceability,
  /// atomically sealing the SLA timers inline.
  Future<void> handle(DisputeSanctionCommand command) async {
    // 1. Fail-Fast Tenant Sync (INV-1, INV-22)
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check (same authorization required as reject)
    if (!_rbac.can(command.callerRole, UserPermission.canRejectSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 3. Load entry scoped to organizationId (tenant isolation, INV-6)
    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    // 4. Idempotency guard (INV-24): only pending entries can transition
    if (entry.status != SanctionReviewStatus.pending) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is already ${entry.status.name}.',
      );
    }

    // 5. Atomic write (lock → re-check → ledger append → queue flip → seal timers)
    await _reviewRepo.disputeSanction(
      organizationId: command.organizationId,
      queueEntryId: command.queueEntryId,
      disputedByUserId: command.disputedByUserId,
      actorEmail: command.actorEmail,
      occurredAtUtc: _dateTimeProvider.nowUtc(),
    );
  }
}
