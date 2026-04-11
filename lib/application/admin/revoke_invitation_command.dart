import 'package:veraprob/domain/enums/user_role.dart';

/// Immutable command DTO for revoking a pending invitation.
///
/// Contains ZERO logic. Revokes the INVITATION — not the user's membership.
/// Use [RemoveMemberCommand] to remove an existing org member.
///
/// [organizationId] and [callerRole] must be injected from the authenticated JWT.
class RevokeInvitationCommand {
  final String organizationId;
  final UserRole callerRole;
  final String invitationId;

  /// Session ID for tenant validation.
  final String sessionId;

  const RevokeInvitationCommand({
    required this.organizationId,
    required this.callerRole,
    required this.invitationId,
    required this.sessionId,
  });
}
