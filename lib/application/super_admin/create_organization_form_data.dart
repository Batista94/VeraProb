import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';

/// Mutable form DTO for the Create Organization wizard.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// - The `capabilities` field is typed as [OrgCapabilitiesViewModel] — a
///   primitive-only projection that the presentation layer can hold safely.
/// - The conversion to the domain type [OrgCapabilities] happens inside
///   [toCommand], keeping domain types entirely within the application layer.
///
/// INV-18: Use typed values (PlanType) instead of raw strings for plan type.
class CreateOrganizationFormData {
  final String legalName;
  final String tradeName;
  final String cnpj;
  final String timezone;
  final String currencyCode;
  final PlanType planType;
  final int? maxVehicles;
  final int? maxActiveContracts;
  final String initialAdminEmail;
  final String superAdminUserId;

  /// Capabilities as a presentation-safe ViewModel.
  /// Converted to [OrgCapabilities] inside [toCommand].
  final OrgCapabilitiesViewModel capabilities;

  final int? toolCostCents;
  final int dwellTimeSeconds;

  const CreateOrganizationFormData({
    required this.legalName,
    required this.tradeName,
    required this.cnpj,
    required this.timezone,
    required this.currencyCode,
    required this.planType,
    this.maxVehicles,
    this.maxActiveContracts,
    required this.initialAdminEmail,
    required this.superAdminUserId,
    this.capabilities = OrgCapabilitiesViewModel.defaults,
    this.toolCostCents,
    this.dwellTimeSeconds = 300,
  });

  CreateOrganizationCommand toCommand() {
    return CreateOrganizationCommand(
      legalName: legalName,
      tradeName: tradeName,
      cnpj: cnpj,
      timezone: timezone,
      currencyCode: currencyCode,
      planType: planType,
      maxVehicles: maxVehicles,
      maxActiveContracts: maxActiveContracts,
      initialAdminEmail: initialAdminEmail,
      superAdminUserId: superAdminUserId,
      // Domain conversion at the application boundary — not in features/
      capabilities: capabilities.toDomain(),
      toolCostCents: toolCostCents,
      dwellTimeSeconds: dwellTimeSeconds,
    );
  }
}
