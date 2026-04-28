import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/domain/super_admin/plan_type.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';

/// Application handler for [UpdateOrganizationQuotaCommand].
///
/// Orchestrates: RBAC → validation → repository update → governance audit log.
///
/// INV-4: Pure orchestration — no direct DB access.
/// INV-7: Billing event is appended server-side inside the RPC.
/// Stage C: Mandatory reason for governance changes.
class UpdateOrganizationQuotaHandler {
  final TenantValidationService _tenantValidator;
  final ISuperAdminRepository _repository;
  final SystemAuditLogService? _auditLogService;
  final RbacService _rbac = RbacService();

  UpdateOrganizationQuotaHandler({
    required TenantValidationService tenantValidator,
    required ISuperAdminRepository repository,
    SystemAuditLogService? auditLogService,
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _auditLogService = auditLogService;

  Future<void> handle(UpdateOrganizationQuotaCommand cmd) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: cmd.organizationId,
      sessionId: cmd.sessionId,
    );

    // ── Step 2: RBAC — before any I/O
    if (!_rbac.can(UserRole.superAdmin, UserPermission.canManageTenants)) {
      throw const DomainException('Unauthorized: canManageTenants required.');
    }

    // ── Step 3: Validate reason (Stage C — mandatory for governance)
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

    // ── Step 4: Validate plan type
    final validPlan = PlanType.values.any((p) => p.dbValue == cmd.newPlanType);
    if (!validPlan) {
      throw DomainException('Tipo de plano inválido: ${cmd.newPlanType}.');
    }

    // ── Step 5: Validate limits
    if (cmd.newMaxVehicles != null && cmd.newMaxVehicles! < 1) {
      throw const DomainException('Limite de veículos deve ser pelo menos 1.');
    }
    if (cmd.newMaxActiveContracts != null && cmd.newMaxActiveContracts! < 1) {
      throw const DomainException(
        'Limite de contratos ativos deve ser pelo menos 1.',
      );
    }

    // ── Step 5a: tool_cost_cents required
    if (cmd.toolCostCents == null) {
      throw const DomainException(
        'Custo mensal da ferramenta é obrigatório para calcular o ROI.',
      );
    }

    // ── Step 6: Delegate to repository
    try {
      await _repository.updateOrganizationQuota(cmd);
    } on PostgrestException catch (e) {
      if (e.code == 'P0001') {
        throw DomainException(e.message);
      }
      rethrow;
    }

    // ── Step 7: Log governance change (Stage C)
    if (_auditLogService != null) {
      await _auditLogService.logGovernanceChange(
        eventType: 'QUOTA_CHANGE',
        reason: cmd.reason!,
        actorType: ActorType.human,
        organizationId: cmd.organizationId,
        oldSnapshot: {'plan_type': 'previous'},
        newSnapshot: {
          'plan_type': cmd.newPlanType,
          'max_vehicles': cmd.newMaxVehicles,
          'max_active_contracts': cmd.newMaxActiveContracts,
          'tool_cost_cents': cmd.toolCostCents,
          'dwell_time_seconds': cmd.dwellTimeSeconds,
        },
      );
    }
  }
}
