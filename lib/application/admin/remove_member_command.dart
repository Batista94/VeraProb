import 'package:veraprob/application/shared/app_types.dart';

/// Command to remove a member from an organization.
///
/// RBAC-enabled: requires [UserPermission.canManageUsers].
class RemoveMemberCommand {
  final String organizationId;
  final UserRole callerRole;
  final String callerUserId;
  final String targetUserId;

  /// Session ID for tenant validation.
  final String sessionId;

  const RemoveMemberCommand({
    required this.organizationId,
    required this.callerRole,
    required this.callerUserId,
    required this.targetUserId,
    required this.sessionId,
  });
}
