import 'package:veraprob/application/shared/app_types.dart';

/// Port for user management mutations (RBAC, member removal, deactivation).
///
/// Decoupled from infrastructure implementations (Supabase RPCs).
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

  Future<void> deactivateMember({
    required String organizationId,
    required String targetUserId,
  });
}
