import 'package:uuid/uuid.dart';
import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/domain_exception.dart';
import 'invitation_command_service.dart';
import 'invite_user_command.dart';

/// Application handler for [InviteUserCommand].
///
/// RBAC: Requires [UserPermission.canInviteUsers] (admin only).
///
/// Token and invitation ID are generated in Dart — never in SQL — to
/// satisfy Invariant 7 (Deterministic Replay). Returns the one-time
/// token so the UI can display the invitation link for copying.
class InviteUserHandler {
  final InvitationCommandService _commandService;
  final RbacService _rbac = RbacService();

  static const int _ttlDays = 7;

  InviteUserHandler(this._commandService);

  /// Handles the command by creating a new invitation.
  ///
  /// Returns the one-time invitation [token] for link generation.
  ///
  /// Throws [DomainException] if:
  /// - [callerRole] does not have [UserPermission.canInviteUsers]
  /// - [email] is blank or missing '@'
  Future<String> handle(InviteUserCommand command) async {
    // 1. RBAC check — before any I/O
    if (!_rbac.can(command.callerRole, UserPermission.canInviteUsers)) {
      throw const DomainException('Unauthorized: canInviteUsers required.');
    }

    // 2. Lightweight email validation
    final email = command.email.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      throw const DomainException('Invalid email address.');
    }

    // 3. Generate IDs in Dart (Invariant 7: Deterministic Replay)
    const uuid = Uuid();
    final invitationId = uuid.v4();
    final token = uuid.v4();
    final expiresAtUtc = DateTime.now().toUtc().add(
      const Duration(days: _ttlDays),
    );

    // 4. Delegate — RPC atomically revokes any existing pending invite + inserts new one
    await _commandService.inviteUser(
      email: email,
      role: command.roleToAssign,
      token: token,
      invitationId: invitationId,
      expiresAtUtc: expiresAtUtc,
    );

    // 5. Return token for UI to build the invitation link
    return token;
  }
}
