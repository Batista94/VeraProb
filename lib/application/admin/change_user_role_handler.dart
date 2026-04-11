import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'change_user_role_command.dart';
import 'user_management_command_service.dart';

/// Application handler for changing a user's role.
///
/// RBAC: Requires [UserPermission.canManageUsers].
class ChangeUserRoleHandler {
  final TenantValidationService _tenantValidator;
  final UserManagementCommandService _commandService;
  final RbacService _rbac = RbacService();

  ChangeUserRoleHandler({
    required TenantValidationService tenantValidator,
    required UserManagementCommandService commandService,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService;

  Future<void> handle(ChangeUserRoleCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check
    if (!_rbac.can(command.callerRole, UserPermission.canManageUsers)) {
      throw DomainException(
        'Unauthorized: Caller identifies as ${command.callerRole} but needs canManageUsers permission',
      );
    }

    // 3. Delegate to command service (RPC)
    await _commandService.changeRole(
      organizationId: command.organizationId,
      targetUserId: command.targetUserId,
      newRole: command.newRole,
    );
  }
}
