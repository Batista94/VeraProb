import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../../infrastructure/admin/postgres_user_management_query_service.dart';
import 'remove_member_command.dart';
import 'user_management_command_service.dart';

/// Application handler for removing a member from an organization.
///
/// RBAC: Requires [UserPermission.canManageUsers].
/// Invariant: Cannot remove the last administrator (belt-and-suspenders with SQL).
class RemoveMemberHandler {
  final UserManagementCommandService _commandService;
  final PostgresUserManagementQueryService _queryService;
  final RbacService _rbac = RbacService();

  RemoveMemberHandler({
    required UserManagementCommandService commandService,
    required PostgresUserManagementQueryService queryService,
  }) : _commandService = commandService,
       _queryService = queryService;

  Future<void> handle(RemoveMemberCommand command) async {
    // 1. RBAC check
    if (!_rbac.can(command.callerRole, UserPermission.canManageUsers)) {
      throw Exception(
        'Unauthorized: Caller identifies as ${command.callerRole} but needs canManageUsers permission',
      );
    }

    // 2. Fetch members to verify "last admin" invariant
    final members = await _queryService.getMembers();

    // Find target
    final target = members
        .where((m) => m.userId == command.targetUserId)
        .firstOrNull;
    if (target == null) {
      throw Exception('Membro não encontrado na organização.');
    }

    // 3. Last-admin guard (Dart level for immediate UX)
    if (target.role == 'TENANT_ADMIN') {
      final adminCount = members.where((m) => m.role == 'TENANT_ADMIN').length;
      if (adminCount <= 1) {
        throw Exception(
          'Não é possível remover o único administrador da organização.',
        );
      }
    }

    // 4. Delegate to command service (RPC)
    await _commandService.removeMember(
      organizationId: command.organizationId,
      targetUserId: command.targetUserId,
    );
  }
}
