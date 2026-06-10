import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'decline_peer_review_command.dart';

/// Application handler for [DeclinePeerReviewCommand] (dual-control decline).
///
/// Reverts a `pending_peer_review` item to its origin (`pending` or `disputed`)
/// and appends `PEER_REVIEW_DECLINED`. Allowed to any auditor — including the
/// first reviewer withdrawing their own request — so it requires rejection
/// authority, not seal authority.
///
/// The atomic write is a single call to
/// [SanctionReviewCommandRepository.declinePeerReview]; the fail-fast guards
/// below are UX/anti-oracle only.
class DeclinePeerReviewHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SanctionReviewCommandRepository _reviewRepo;
  final RbacService _rbac;
  final IDateTimeProvider _clock;

  DeclinePeerReviewHandler({
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

  Future<void> handle(DeclinePeerReviewCommand command) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    if (!_rbac.can(command.callerRole, UserPermission.canRejectSanctions)) {
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

    await _reviewRepo.declinePeerReview(
      organizationId: command.organizationId,
      queueEntryId: command.queueEntryId,
      reviewedByUserId: command.declinedByUserId,
      actorEmail: command.actorEmail,
      reason: command.reason,
      occurredAtUtc: _clock.nowUtc(),
    );
  }
}
