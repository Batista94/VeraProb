import 'package:veraprob/domain/enums/user_role.dart';

class ChangeUserRoleCommand {
  final String organizationId;
  final UserRole callerRole;
  final String targetUserId;
  final UserRole newRole;

  /// Session ID for tenant validation.
  final String sessionId;

  const ChangeUserRoleCommand({
    required this.organizationId,
    required this.callerRole,
    required this.targetUserId,
    required this.newRole,
    required this.sessionId,
  });
}
