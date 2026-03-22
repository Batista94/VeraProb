import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/domain_exception.dart';
import 'change_user_role_command.dart';
import 'user_management_command_service.dart';

/// Application handler for changing a user's role.
///
/// RBAC: Requires [UserPermission.canManageUsers].
class ChangeUserRoleHandler {
  final UserManagementCommandService _commandService;
  final RbacService _rbac = RbacService();

  ChangeUserRoleHandler(this._commandService);

  Future<void> handle(ChangeUserRoleCommand command) async {
    // 1. RBAC check
    if (!_rbac.can(command.callerRole, UserPermission.canManageUsers)) {
      throw DomainException(
        'Unauthorized: Caller identifies as ${command.callerRole} but needs canManageUsers permission',
      );
    }

    // 2. Delegate to command service (RPC)
    await _commandService.changeRole(
      organizationId: command.organizationId,
      targetUserId: command.targetUserId,
      newRole: command.newRole,
    );
  }
}
