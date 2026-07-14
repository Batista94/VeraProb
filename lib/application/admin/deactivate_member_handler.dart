import 'package:veraprob/application/admin/remove_member_command.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';

/// Application handler for deactivating (not deleting) a member.
///
/// RBAC: Requires [UserPermission.canManageUsers].
/// Invariant: Cannot deactivate the last administrator.
/// Invariant: Cannot deactivate yourself (self-protection).
/// INV-3: Never deletes — sets is_active = false for forensic history.
class DeactivateMemberHandler {
  final TenantValidationService _tenantValidator;
  final UserManagementCommandService _commandService;
  final UserManagementQueryService _queryService;
  final RbacService _rbac = RbacService();

  DeactivateMemberHandler({
    required TenantValidationService tenantValidator,
    required UserManagementCommandService commandService,
    required UserManagementQueryService queryService,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService,
       _queryService = queryService;

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

    if (command.callerUserId == command.targetUserId) {
      throw const DomainException('Nao e possivel inativar o proprio usuario.');
    }

    final members = await _queryService.getMembers();

    final target = members
        .where((m) => m.userId == command.targetUserId)
        .firstOrNull;
    if (target == null) {
      throw const DomainException('Membro nao encontrado na organizacao.');
    }

    if (target.role == UserRole.admin) {
      final adminCount = members.where((m) => m.role == UserRole.admin).length;
      if (adminCount <= 1) {
        throw const DomainException(
          'Nao e possivel inativar o unico administrador da organizacao.',
        );
      }
    }

    await _commandService.deactivateMember(
      organizationId: command.organizationId,
      targetUserId: command.targetUserId,
    );
  }
}
