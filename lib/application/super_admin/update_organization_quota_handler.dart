import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/enums/user_permissions.dart';
import '../../domain/enums/user_role.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/domain_exception.dart';
import '../../domain/super_admin/i_super_admin_repository.dart';
import '../../domain/super_admin/plan_type.dart';
import '../../domain/super_admin/update_organization_quota_command.dart';

/// Application handler for [UpdateOrganizationQuotaCommand].
///
/// Orchestrates: RBAC → validation → repository update.
///
/// INV-4: Pure orchestration — no direct DB access.
/// INV-7: Billing event is appended server-side inside the RPC.
class UpdateOrganizationQuotaHandler {
  final ISuperAdminRepository _repository;
  final RbacService _rbac = RbacService();

  UpdateOrganizationQuotaHandler(this._repository);

  Future<void> handle(UpdateOrganizationQuotaCommand cmd) async {
    // 1. RBAC — before any I/O
    if (!_rbac.can(UserRole.superAdmin, UserPermission.canManageTenants)) {
      throw const DomainException('Unauthorized: canManageTenants required.');
    }

    // 2. Validate plan type
    final validPlan = PlanType.values.any((p) => p.dbValue == cmd.newPlanType);
    if (!validPlan) {
      throw DomainException('Tipo de plano inválido: ${cmd.newPlanType}.');
    }

    // 3. Validate limits — non-null must be >= 1; null = unlimited (enterprise)
    if (cmd.newMaxVehicles != null && cmd.newMaxVehicles! < 1) {
      throw const DomainException('Limite de veículos deve ser pelo menos 1.');
    }
    if (cmd.newMaxActiveContracts != null && cmd.newMaxActiveContracts! < 1) {
      throw const DomainException(
        'Limite de contratos ativos deve ser pelo menos 1.',
      );
    }

    // 4. Delegate to repository
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
