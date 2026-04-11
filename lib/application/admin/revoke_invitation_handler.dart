import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'invitation_command_service.dart';
import 'revoke_invitation_command.dart';

/// Application handler for [RevokeInvitationCommand].
///
/// RBAC: Requires [UserPermission.canInviteUsers] (admin only).
class RevokeInvitationHandler {
  final TenantValidationService _tenantValidator;
  final InvitationCommandService _commandService;
  final RbacService _rbac = RbacService();

  RevokeInvitationHandler({
    required TenantValidationService tenantValidator,
    required InvitationCommandService commandService,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService;

  /// Handles the command by revoking the pending invitation.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canInviteUsers]
  Future<void> handle(RevokeInvitationCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check — before any I/O
    if (!_rbac.can(command.callerRole, UserPermission.canInviteUsers)) {
      throw const DomainException('Unauthorized: canInviteUsers required.');
    }

    // 2. Delegate — server-side validates org scope
    await _commandService.revokeInvitation(invitationId: command.invitationId);
  }
}
