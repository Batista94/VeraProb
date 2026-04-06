import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'invitation_command_service.dart';
import 'revoke_invitation_command.dart';

/// Application handler for [RevokeInvitationCommand].
///
/// RBAC: Requires [UserPermission.canInviteUsers] (admin only).
class RevokeInvitationHandler {
  final InvitationCommandService _commandService;
  final RbacService _rbac = RbacService();

  RevokeInvitationHandler(this._commandService);

  /// Handles the command by revoking the pending invitation.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canInviteUsers]
  Future<void> handle(RevokeInvitationCommand command) async {
    // 1. RBAC check — before any I/O
    if (!_rbac.can(command.callerRole, UserPermission.canInviteUsers)) {
      throw const DomainException('Unauthorized: canInviteUsers required.');
    }

    // 2. Delegate — server-side validates org scope
    await _commandService.revokeInvitation(invitationId: command.invitationId);
  }
}
