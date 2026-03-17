import 'invitation.dart';

/// Read-side port for invitation queries.
/// Concrete implementation: [PostgresInvitationQueryService].
abstract class InvitationRepository {
  /// Returns all invitations for [organizationId], any status, newest first.
  Future<List<Invitation>> listByOrganization(String organizationId);

  /// Returns the invitation matching [token] only if it is still active
  /// (not expired, not accepted, not revoked). Returns null otherwise.
  Future<Invitation?> findActiveByToken(String token);
}
