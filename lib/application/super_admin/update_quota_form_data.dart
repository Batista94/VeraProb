import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/super_admin/update_organization_quota_command.dart';

/// Mutable form DTO for the Update Quota dialog.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// - All fields are primitives or application-layer ViewModels.
/// - [OrgCapabilities] (domain) is never exposed here; the `capabilities`
///   field uses [OrgCapabilitiesViewModel] instead.
/// - Call [toCommand] to produce the [UpdateOrganizationQuotaCommand]
///   for dispatch — domain conversion happens inside [toCommand], not in
///   the presentation layer.
class UpdateQuotaFormData {
  final String organizationId;
  final String newPlanType;
  final int? newMaxVehicles;
  final int? newMaxActiveContracts;
  final String superAdminUserId;
  final String? reason;

  /// Capabilities as a presentation-safe ViewModel.
  /// Converted to [OrgCapabilities] inside [toCommand].
  final OrgCapabilitiesViewModel? capabilities;

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
      // Domain conversion at the application boundary — not in features/
      capabilities: capabilities?.toDomain(),
      toolCostCents: toolCostCents,
      dwellTimeSeconds: dwellTimeSeconds,
    );
  }
}
