import '../../domain/enums/user_role.dart';

/// Port for user management mutations (RBAC, member removal).
abstract class UserManagementCommandService {
  Future<void> changeRole({
    required String organizationId,
    required String targetUserId,
    required UserRole newRole,
  });

  Future<void> removeMember({
    required String organizationId,
    required String targetUserId,
  });
}
