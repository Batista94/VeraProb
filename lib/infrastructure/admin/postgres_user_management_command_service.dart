import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/domain/enums/user_role.dart';

/// PostgreSQL implementation of [UserManagementCommandService] using Supabase RPCs.
class PostgresUserManagementCommandService
    implements UserManagementCommandService {
  final SupabaseClient _client;

  PostgresUserManagementCommandService(this._client);

  @override
  Future<void> changeRole({
    required String organizationId,
    required String targetUserId,
    required UserRole newRole,
  }) async {
    final dbRole = _mapRoleToDb(newRole);
    await _client.rpc(
      'update_member_role',
      params: {'p_target_user_id': targetUserId, 'p_new_role': dbRole},
    );
  }

  @override
  Future<void> removeMember({
    required String organizationId,
    required String targetUserId,
  }) async {
    await _client.rpc(
      'remove_member',
      params: {'p_target_user_id': targetUserId},
    );
  }

  @override
  Future<void> deactivateMember({
    required String organizationId,
    required String targetUserId,
  }) async {
    await _client.rpc(
      'deactivate_member',
      params: {'p_target_user_id': targetUserId},
    );
  }

  String _mapRoleToDb(UserRole role) {
    switch (role) {
      case UserRole.admin:
        return 'TENANT_ADMIN';
      case UserRole.operator:
        return 'OPERATOR';
      case UserRole.auditor:
        return 'AUDITOR';
      case UserRole.contractorViewer:
        return 'CONTRACTOR_VIEWER';
      case UserRole.superAdmin:
        throw ArgumentError(
          'superAdmin is not a tenant role and cannot be assigned via user management',
        );
    }
  }
}
