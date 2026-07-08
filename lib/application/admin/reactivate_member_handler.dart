import 'package:veraprob/application/admin/remove_member_command.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';

/// Application handler for reactivating a previously deactivated (archived)
/// member. Restores `user_roles.is_active = true` for reactivation/consultation.
///
/// RBAC: Requires [UserPermission.canManageUsers]. No last-admin logic —
/// reactivation only adds access, never removes it. Reuses [RemoveMemberCommand]
/// (member-target shape) as the sibling [DeactivateMemberHandler] does.
class ReactivateMemberHandler {
  final TenantValidationService _tenantValidator;
  final UserManagementCommandService _commandService;
  final RbacService _rbac = RbacService();

  ReactivateMemberHandler({
    required TenantValidationService tenantValidator,
    required UserManagementCommandService commandService,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService;

  Future<void> handle(RemoveMemberCommand command) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    if (!_rbac.can(command.callerRole, UserPermission.canManageUsers)) {
      throw const DomainException(
        'Unauthorized: canManageUsers permission required',
      );
    }

    await _commandService.reactivateMember(
      organizationId: command.organizationId,
      targetUserId: command.targetUserId,
    );
  }
}
