import 'package:veraprob/application/admin/remove_member_command.dart';
import 'package:veraprob/application/admin/user_management_command_service.dart';
import 'package:veraprob/application/admin/user_management_query_service.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';

/// Application handler for removing a member from an organization.
///
/// RBAC: Requires [UserPermission.canManageUsers].
/// Invariant: Cannot remove the last administrator (belt-and-suspenders with SQL).
class RemoveMemberHandler {
  final TenantValidationService _tenantValidator;
  final UserManagementCommandService _commandService;
  final UserManagementQueryService _queryService;
  final RbacService _rbac = RbacService();

  RemoveMemberHandler({
    required TenantValidationService tenantValidator,
    required UserManagementCommandService commandService,
    required UserManagementQueryService queryService,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService,
       _queryService = queryService;

  Future<void> handle(RemoveMemberCommand command) async {
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

    // 2. Fetch members to verify "last admin" invariant
    final members = await _queryService.getMembers();

    // Find target
    final target = members
        .where((m) => m.userId == command.targetUserId)
        .firstOrNull;
    if (target == null) {
      throw const DomainException('Membro não encontrado na organização.');
    }

    // 3. Last-admin guard (Dart level for immediate UX)
    if (target.role == UserRole.admin) {
      final adminCount = members.where((m) => m.role == UserRole.admin).length;
      if (adminCount <= 1) {
        throw const DomainException(
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
