import '../../domain/enums/user_role.dart';

class ChangeUserRoleCommand {
  final String organizationId;
  final UserRole callerRole;
  final String targetUserId;
  final UserRole newRole;

  const ChangeUserRoleCommand({
    required this.organizationId,
    required this.callerRole,
    required this.targetUserId,
    required this.newRole,
  });
}
