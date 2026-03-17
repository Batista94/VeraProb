/// Immutable command DTO for accepting a contract via a public review token.
///
/// Contains ZERO logic. No [callerRole] or [organizationId] — token possession
/// is the sole authorization credential (mirrors [AcceptInvitationCommand]).
///
/// The [token] comes from the URL query parameter `?token=...` on the public
/// review page. The handler validates it server-side via the RPC.
class AcceptByContractorCommand {
  final String token;

  const AcceptByContractorCommand({required this.token});
}
