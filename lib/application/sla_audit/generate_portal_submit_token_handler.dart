import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_command_repository.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';
import 'generate_portal_submit_token_command.dart';

/// Application handler for [GeneratePortalSubmitTokenCommand].
///
/// Mints a submit-scoped, TTL-bounded portal token so an external carrier can
/// view the sealed verdict and submit counter-evidence. The authoritative checks
/// (RBAC, status, advisory lock, ledger fact) live in the
/// `generate_portal_submit_token` SECURITY DEFINER RPC.
class GeneratePortalSubmitTokenHandler {
  final TenantValidationService _tenantValidator;
  final SanctionReviewQueueRepository _queueRepo;
  final SanctionReviewCommandRepository _reviewRepo;
  final RbacService _rbac;

  GeneratePortalSubmitTokenHandler({
    required TenantValidationService tenantValidator,
    required SanctionReviewQueueRepository queueRepo,
    required SanctionReviewCommandRepository reviewRepo,
    required RbacService rbac,
  }) : _tenantValidator = tenantValidator,
       _queueRepo = queueRepo,
       _reviewRepo = reviewRepo,
       _rbac = rbac;

  /// Returns the opaque UUID token. The caller builds the portal URL
  /// (`/portal/dispute?token=<uuid>`) and hands it to the carrier.
  ///
  /// Throws [DomainException] if the caller lacks authorization, the entry is
  /// not found for [organizationId], or the entry is not contested
  /// (`disputed`).
  Future<String> handle(GeneratePortalSubmitTokenCommand command) async {
    // 1. INV-1 Fail-Fast tenant sync.
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC — same authorization tier as dispute resolution.
    if (!_rbac.can(command.callerRole, UserPermission.canRejectSanctions)) {
      throw const DomainException('Unauthorized.');
    }

    // 3. Load entry scoped to organizationId (tenant isolation, INV-1).
    final entry = await _queueRepo.findById(
      command.queueEntryId,
      organizationId: command.organizationId,
    );
    if (entry == null) {
      throw DomainException(
        'Sanction queue entry "${command.queueEntryId}" not found.',
      );
    }

    // 4. A submit portal link is only meaningful for a disputed verdict.
    if (entry.status != SanctionReviewStatus.disputed) {
      throw DomainException(
        'Sanction "${command.queueEntryId}" is not disputed '
        '(${entry.status.name}).',
      );
    }

    return _reviewRepo.generatePortalSubmitToken(
      organizationId: command.organizationId,
      queueEntryId: command.queueEntryId,
      createdByUserId: command.createdByUserId,
    );
  }
}
