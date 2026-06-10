import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'confirm_peer_review_command.dart';

/// Application handler for [ConfirmPeerReviewCommand] (dual-control confirm).
///
/// The SECOND auditor finalizes a high-value verdict held in
/// `pending_peer_review`. The terminal action (`applied`/`rejected`) is the one
/// proposed by the first reviewer; this handler does not re-decide it.
///
/// **Anti-fraud (DB-enforced):** the write is a single call to
/// [SanctionReviewCommandRepository.confirmPeerReview], backed by the
/// `confirm_peer_review` SECURITY DEFINER RPC. The RPC binds the confirming
/// identity to the JWT `sub` and raises `DualControlSelfApprovalException` if it
/// equals the first reviewer — reviewer2 != reviewer1 is a server-side
/// guarantee, NOT a client check. The fail-fast guards below are UX/anti-oracle
/// only.
class ConfirmPeerReviewHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SanctionReviewCommandRepository _reviewRepo;
  final RbacService _rbac;
  final IDateTimeProvider _clock;

  ConfirmPeerReviewHandler({
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

  /// Throws [DomainException] if unauthorized, entry missing, or the entry is
  /// not awaiting a second auditor. Propagates `DualControlSelfApprovalException`
  /// from the RPC when the confirmer is the requester.
  Future<void> handle(ConfirmPeerReviewCommand command) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // Confirming finalizes a verdict — requires seal authority.
    if (!_rbac.can(command.callerRole, UserPermission.canApproveSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    if (entry.status != SanctionReviewStatus.pendingPeerReview) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is not awaiting a second auditor.',
      );
    }

    await _reviewRepo.confirmPeerReview(
      organizationId: command.organizationId,
      queueEntryId: command.queueEntryId,
      reviewedByUserId: command.confirmedByUserId,
      actorEmail: command.actorEmail,
      occurredAtUtc: _clock.nowUtc(),
    );
  }
}
