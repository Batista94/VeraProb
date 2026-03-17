import '../../domain/sla_audit/domain_exception.dart';
import 'accept_invitation_command.dart';
import 'invitation_command_service.dart';

/// Application handler for [AcceptInvitationCommand].
///
/// This is a PUBLIC operation — no RBAC check.
/// Authority is granted solely by possession of the one-time token.
///
/// The [InvitationCommandService.acceptInvitation] RPC performs server-side:
/// - Row-level lock (FOR UPDATE) to prevent double-acceptance
/// - Token validity check (not expired, not revoked, not accepted)
/// - accepted_at_utc stamped atomically
/// - user_roles INSERT ON CONFLICT DO NOTHING
class AcceptInvitationHandler {
  final InvitationCommandService _commandService;

  AcceptInvitationHandler(this._commandService);

  /// Handles the command by accepting the invitation and provisioning the user.
  ///
  /// Throws [DomainException] if:
  /// - [token] is blank (fast-fail before network call)
  /// - [userId] is blank (user must be authenticated)
  /// Server-side RPC also throws if token is expired/revoked/already accepted.
  Future<void> handle(AcceptInvitationCommand command) async {
    if (command.token.trim().isEmpty) {
      throw const DomainException('Invalid invitation token.');
    }
    if (command.userId.trim().isEmpty) {
      throw const DomainException(
          'User must be authenticated to accept an invitation.');
    }

    await _commandService.acceptInvitation(
      token: command.token,
      userId: command.userId,
    );
  }
}
