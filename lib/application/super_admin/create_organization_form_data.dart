import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';

/// Mutable form DTO for the Create Organization wizard.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// - The `capabilities` field is typed as [OrgCapabilitiesViewModel].
/// - The conversion to the domain type [OrgCapabilities] happens inside
///   [toCommand], keeping domain types entirely within the application layer.
class CreateOrganizationFormData {
  final String legalName;
  final String tradeName;
  final String cnpj;
  final String timezone;
  final String currencyCode;
  final PlanType planType;
  final int? maxVehicles;
  final int? maxActiveContracts;
  final List<String> adminEmails;
  final String superAdminUserId;
  final OrgCapabilitiesViewModel capabilities;
  final int? toolCostCents;
  final int dwellTimeSeconds;
  final String? reason;
  final int? billingDay;
  final String? contactEmail;
  final String? externalId;
  final List<String> allowedDomains;

  const CreateOrganizationFormData({
    required this.legalName,
    required this.tradeName,
    required this.cnpj,
    required this.timezone,
    required this.currencyCode,
    required this.planType,
    this.maxVehicles,
    this.maxActiveContracts,
    required this.adminEmails,
    required this.superAdminUserId,
    this.capabilities = OrgCapabilitiesViewModel.defaults,
    this.toolCostCents,
    this.dwellTimeSeconds = 300,
    this.reason,
    this.billingDay,
    this.contactEmail,
    this.externalId,
    this.allowedDomains = const [],
  });

  CreateOrganizationCommand toCommand() {
    if (billingDay != null && (billingDay! < 1 || billingDay! > 28)) {
      throw IntegrityException(
        'billingDay must be between 1 and 28, got $billingDay',
        field: 'billing_day',
      );
    }
    if (externalId != null && externalId!.length > 100) {
      throw IntegrityException(
        'externalId must not exceed 100 characters, got ${externalId!.length}',
        field: 'external_id',
      );
    }

    return CreateOrganizationCommand(
      legalName: legalName,
      tradeName: tradeName,
      cnpj: cnpj,
      timezone: timezone,
      currencyCode: currencyCode,
      planType: planType,
      maxVehicles: maxVehicles,
      maxActiveContracts: maxActiveContracts,
      adminEmails: adminEmails,
      superAdminUserId: superAdminUserId,
      capabilities: capabilities.toDomain(),
      toolCostCents: toolCostCents,
      dwellTimeSeconds: dwellTimeSeconds,
      reason: reason,
      billingDay: billingDay,
      contactEmail: contactEmail,
      externalId: externalId,
      allowedDomains: allowedDomains,
    );
  }
}
