import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';

/// Mutable form DTO for the Update Quota dialog.
///
/// All fields are primitives — no domain types leak into features/.
/// Call [toCommand] to produce the [UpdateOrganizationQuotaCommand] for dispatch.
class UpdateQuotaFormData {
  final String organizationId;
  final String newPlanType;
  final int? newMaxVehicles;
  final int? newMaxActiveContracts;
  final String superAdminUserId;
  final String? reason;
  final OrgCapabilities? capabilities;
  final int? toolCostCents;
  final int? dwellTimeSeconds;

  const UpdateQuotaFormData({
    required this.organizationId,
    required this.newPlanType,
    this.newMaxVehicles,
    this.newMaxActiveContracts,
    required this.superAdminUserId,
    this.reason,
    this.capabilities,
    this.toolCostCents,
    this.dwellTimeSeconds,
  });

  UpdateOrganizationQuotaCommand toCommand() {
    if (toolCostCents == null) {
      throw const DomainException(
        'Custo mensal da ferramenta é obrigatório para calcular o ROI.',
      );
    }
    return UpdateOrganizationQuotaCommand(
      organizationId: organizationId,
      newPlanType: newPlanType,
      newMaxVehicles: newMaxVehicles,
      newMaxActiveContracts: newMaxActiveContracts,
      superAdminUserId: superAdminUserId,
      reason: reason,
      sessionId: '', // super-admin context — no regular session
      capabilities: capabilities,
      toolCostCents: toolCostCents,
      dwellTimeSeconds: dwellTimeSeconds,
    );
  }
}
