import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
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

  /// Mandatory justification for the ORG_CREATED audit log entry.
  /// The UI always requires this; null is only valid for test callers.
  final String? reason;

  /// Preferred billing day of month (1–28). Null = platform default.
  final int? billingDay;

  /// Primary billing/ops contact email. Null = use admin email.
  final String? contactEmail;

  /// External reference ID from a 3rd-party system (CRM, ERP). Max 100 chars.
  final String? externalId;

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
    this.reason,
    this.billingDay,
    this.contactEmail,
    this.externalId,
  });

  CreateOrganizationCommand toCommand() {
    // billingDay must be 1–28 (all months guarantee day 28 exists — INV-10)
    if (billingDay != null && (billingDay! < 1 || billingDay! > 28)) {
      throw IntegrityException(
        'billingDay must be between 1 and 28, got $billingDay',
        field: 'billing_day',
      );
    }

    // externalId is an opaque reference — length cap prevents DB overflow (INV-10)
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
      initialAdminEmail: initialAdminEmail,
      superAdminUserId: superAdminUserId,
      // Domain conversion at the application boundary — not in features/
      capabilities: capabilities.toDomain(),
      toolCostCents: toolCostCents,
      dwellTimeSeconds: dwellTimeSeconds,
      reason: reason,
      billingDay: billingDay,
      contactEmail: contactEmail,
      externalId: externalId,
    );
  }
}
