import '../../domain/enums/user_role.dart';

class RemoveMemberCommand {
  final String organizationId;
  final UserRole callerRole;
  final String targetUserId;

  const RemoveMemberCommand({
    required this.organizationId,
    required this.callerRole,
    required this.targetUserId,
  });
}
