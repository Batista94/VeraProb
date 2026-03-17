import '../../domain/enums/user_role.dart';

/// Immutable command DTO for inviting a new user to the organization.
///
/// Contains ZERO logic. Carries only the data required by [InviteUserHandler].
///
/// [organizationId] and [callerRole] must be injected from the authenticated JWT —
/// never from form input. [invitedByUserId] is the Supabase auth UID of the admin.
class InviteUserCommand {
  final String organizationId;
  final UserRole callerRole;
  final String invitedByUserId;
  final String email;
  final UserRole roleToAssign;

  const InviteUserCommand({
    required this.organizationId,
    required this.callerRole,
    required this.invitedByUserId,
    required this.email,
    required this.roleToAssign,
  });
}
