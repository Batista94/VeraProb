import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/plan_type.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';

/// Application handler for [UpdateOrganizationQuotaCommand].
///
/// Orchestrates: RBAC → validation → repository update.
///
/// INV-4: Pure orchestration — no direct DB access.
/// INV-7: Billing event is appended server-side inside the RPC.
class UpdateOrganizationQuotaHandler {
  final TenantValidationService _tenantValidator;
  final ISuperAdminRepository _repository;
  final RbacService _rbac = RbacService();

  UpdateOrganizationQuotaHandler({
    required TenantValidationService tenantValidator,
    required ISuperAdminRepository repository,
  }) : _tenantValidator = tenantValidator,
       _repository = repository;

  Future<void> handle(UpdateOrganizationQuotaCommand cmd) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: cmd.organizationId,
      sessionId: cmd.sessionId,
    );

    // ── Step 2: RBAC — before any I/O ────────────────────────────────────
    if (!_rbac.can(UserRole.superAdmin, UserPermission.canManageTenants)) {
      throw const DomainException('Unauthorized: canManageTenants required.');
    }

    // ── Step 3: Validate plan type ───────────────────────────────────────
    final validPlan = PlanType.values.any((p) => p.dbValue == cmd.newPlanType);
    if (!validPlan) {
      throw DomainException('Tipo de plano inválido: ${cmd.newPlanType}.');
    }

    // ── Step 4: Validate limits — non-null must be >= 1; null = unlimited (enterprise)
    if (cmd.newMaxVehicles != null && cmd.newMaxVehicles! < 1) {
      throw const DomainException('Limite de veículos deve ser pelo menos 1.');
    }
    if (cmd.newMaxActiveContracts != null && cmd.newMaxActiveContracts! < 1) {
      throw const DomainException(
        'Limite de contratos ativos deve ser pelo menos 1.',
      );
    }

    // ── Step 5: Delegate to repository ───────────────────────────────────
    try {
      await _repository.updateOrganizationQuota(cmd);
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        throw DomainException(e.message);
      }
      rethrow;
    }
  }
}
