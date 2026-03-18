import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/domain_exception.dart';
import 'invitation_command_service.dart';
import 'revoke_invitation_command.dart';

/// Application handler for [RevokeInvitationCommand].
///
/// RBAC: Requires [UserPermission.canManageUsers] (admin only).
///
/// Revokes a PENDING invitation. Has no effect on existing members.
/// Use [RemoveMemberHandler] to remove an org member.
class RevokeInvitationHandler {
  final InvitationCommandService _commandService;
  final RbacService _rbac = RbacService();

  RevokeInvitationHandler(this._commandService);

  /// Handles the command by revoking the pending invitation.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canManageUsers]
  /// Server-side RPC also throws if the invitation is already accepted/revoked
  /// or does not belong to the caller's organization.
  Future<void> handle(RevokeInvitationCommand command) async {
    // 1. RBAC check — before any I/O
    if (!_rbac.can(command.callerRole, UserPermission.canManageUsers)) {
      throw const DomainException('Unauthorized: canManageUsers required.');
    }

    // 2. Delegate — server-side validates org scope
    await _commandService.revokeInvitation(invitationId: command.invitationId);
  }
}
