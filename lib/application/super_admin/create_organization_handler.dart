import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/admin/invite_user_handler.dart';
import '../../application/admin/invite_user_command.dart';
import '../../domain/enums/user_permissions.dart';
import '../../domain/enums/user_role.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/super_admin/create_organization_command.dart';
import '../../domain/super_admin/i_super_admin_repository.dart';
import 'create_organization_result.dart';
import 'super_admin_invitation_command_service.dart';

/// Application handler for [CreateOrganizationCommand].
///
/// Orchestrates: RBAC → validation → org creation → billing event → admin invite.
///
/// INV-4: Pure orchestration — no direct DB access.
/// INV-7: IDs generated in Dart (via InviteUserHandler), not in SQL.
class CreateOrganizationHandler {
  final ISuperAdminRepository _repository;
  final SupabaseClient _serviceRoleClient;
  final RbacService _rbac = RbacService();

  CreateOrganizationHandler(this._repository, this._serviceRoleClient);

  Future<CreateOrganizationResult> handle(CreateOrganizationCommand cmd) async {
    // 1. RBAC — before any I/O
    if (!_rbac.can(UserRole.superAdmin, UserPermission.canManageTenants)) {
      throw const DomainException('Unauthorized: canManageTenants required.');
    }

    // 2. CNPJ validation — strip non-digits, must be 14 digits
    final cnpjDigits = cmd.cnpj.replaceAll(RegExp(r'\D'), '');
    if (cnpjDigits.length != 14) {
      throw const DomainException('CNPJ inválido: deve conter 14 dígitos.');
    }

    // 3. Required fields validation
    if (cmd.legalName.trim().isEmpty) {
      throw const DomainException('Razão social é obrigatória.');
    }
    if (cmd.tradeName.trim().isEmpty) {
      throw const DomainException('Nome fantasia é obrigatório.');
    }

    // 4. Email validation
    final email = cmd.initialAdminEmail.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      throw const DomainException('E-mail inválido.');
    }

    // 5. Create org + billing event (atomic RPC via service_role)
    final orgId = await _repository.createOrganization(cmd);

    // 6. Invite first admin via SuperAdminInvitationCommandService (D4: bypasses TENANT_ADMIN check)
    //    IDs generated in Dart by InviteUserHandler — satisfies INV-7.
    final invitationService = SuperAdminInvitationCommandService(
      _serviceRoleClient,
      orgId: orgId,
      superAdminUserId: cmd.superAdminUserId,
    );
    final inviteHandler = InviteUserHandler(invitationService);

    final token = await inviteHandler.handle(
      InviteUserCommand(
        organizationId: orgId,
        callerRole: UserRole.superAdmin,
        invitedByUserId: cmd.superAdminUserId,
        email: email,
        roleToAssign: UserRole.admin,
      ),
    );

    // 7. Return immutable result
    return CreateOrganizationResult(orgId: orgId, invitationToken: token);
  }
}
