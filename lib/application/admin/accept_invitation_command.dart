/// Immutable command DTO for accepting a pending invitation.
///
/// This is a PUBLIC operation — no [callerRole] required.
/// Authority is granted solely by possession of the one-time [token].
///
/// [userId] is the Supabase auth UID of the user accepting the invitation.
/// Must be sourced from the active auth session — never from user input.
class AcceptInvitationCommand {
  final String token;
  final String userId;

  const AcceptInvitationCommand({required this.token, required this.userId});
}
