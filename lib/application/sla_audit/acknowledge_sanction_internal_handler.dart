import 'package:veraprob/application/sla_audit/acknowledge_sanction_internal_command.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_acknowledgement_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';

/// Application handler for [AcknowledgeSanctionInternalCommand].
///
/// Records a TENANT_ADMIN's documentation of an off-band penalty acceptance.
/// Atomicity + authority are DB-enforced (`acknowledge_sanction_internal` RPC:
/// `applied` re-check → INTERNAL_RECORD insert → terminal `acknowledged` flip →
/// `SANCTION_ACKNOWLEDGED` fact, all in one transaction, TENANT_ADMIN-only).
/// The client-side checks are fail-fast UX/anti-oracle guards, not the barrier.
class AcknowledgeSanctionInternalHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SanctionAcknowledgementCommandRepository _ackRepo;
  final RbacService _rbac;

  AcknowledgeSanctionInternalHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SanctionAcknowledgementCommandRepository ackRepo,
    required RbacService rbac,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _ackRepo = ackRepo,
       _rbac = rbac;

  /// Records the acknowledgement, returning the new acknowledgement id.
  ///
  /// Throws [DomainException] if the caller lacks sanction authority, the entry
  /// is not found, or the sanction is not in [SanctionReviewStatus.applied].
  Future<String> handle(AcknowledgeSanctionInternalCommand command) async {
    // 1. INV-1 fail-fast identity sync.
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC fail-fast (the RPC additionally enforces TENANT_ADMIN authority).
    if (!_rbac.can(command.callerRole, UserPermission.canApproveSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 3. Load entry scoped to org (tenant isolation, INV-1). Fail-fast UX guard.
    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    // 4. Only an applied sanction can be acknowledged.
    if (entry.status != SanctionReviewStatus.applied) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is not applied (status: ${entry.status.name}).',
      );
    }

    // 5. Atomic write (DB transaction owns concurrency + authority).
    return _ackRepo.acknowledgeInternal(
      organizationId: command.organizationId,
      queueEntryId: command.queueEntryId,
      acknowledgedByUserId: command.acknowledgedByUserId,
      notes: command.notes,
    );
  }
}
