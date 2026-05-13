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
/// Orchestrates: INV-1 tenant check → RBAC → validation → repository update.
///
/// For SuperAdmin context, inject [SuperAdminBypassTenantValidator] which
/// satisfies INV-1 structurally while being a no-op (SuperAdmin has sovereignty).
///
/// INV-4: Pure orchestration — no direct DB access.
/// INV-3/INV-21: Audit log is written atomically by the RPC (CT11). No
/// second write here — the DB entry is authoritative and includes the full
/// name diff (trade_name / legal_name before/after).
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
    // ── Step 0: INV-1 Identity Sovereignty (no-op for SuperAdmin via bypass validator)
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: cmd.organizationId,
      sessionId: cmd.sessionId,
    );

    // ── Step 1: RBAC — before any I/O
    if (!_rbac.can(UserRole.superAdmin, UserPermission.canManageTenants)) {
      throw const DomainException('Unauthorized: canManageTenants required.');
    }

    // ── Step 2: Validate reason (Stage C — mandatory for governance)
    if (cmd.reason == null || cmd.reason!.trim().isEmpty) {
      throw const DomainException(
        'Justificativa obrigatória para mudanças de cota.',
      );
    }
    if (cmd.reason!.trim().length < 10) {
      throw const DomainException(
        'Justificativa deve ter pelo menos 10 caracteres.',
      );
    }

    // ── Step 3: Validate plan type
    final validPlan = PlanType.values.any((p) => p.dbValue == cmd.newPlanType);
    if (!validPlan) {
      throw DomainException('Tipo de plano inválido: ${cmd.newPlanType}.');
    }

    // ── Step 4: Validate limits
    if (cmd.newMaxVehicles != null && cmd.newMaxVehicles! < 1) {
      throw const DomainException('Limite de veículos deve ser pelo menos 1.');
    }
    if (cmd.newMaxActiveContracts != null && cmd.newMaxActiveContracts! < 1) {
      throw const DomainException(
        'Limite de contratos ativos deve ser pelo menos 1.',
      );
    }
    if (cmd.dwellTimeSeconds != null && cmd.dwellTimeSeconds! < 300) {
      throw const DomainException(
        'Tempo de permanência deve ser pelo menos 300 segundos (5 minutos).',
      );
    }

    // ── Step 4a: tool_cost_cents required
    if (cmd.toolCostCents == null) {
      throw const DomainException(
        'Custo mensal da ferramenta é obrigatório para calcular o ROI.',
      );
    }

    // ── Step 5: Delegate to repository
    // RPC writes system_audit_log atomically with full name diff (CT11, INV-21).
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
