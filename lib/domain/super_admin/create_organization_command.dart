import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/super_admin/plan_type.dart';

/// Immutable command DTO for creating a new tenant organization.
///
/// Carries all information from the 3-step wizard.
/// Contains ZERO logic — pure information transfer.
/// INV-4: Pure Dart — zero infrastructure dependencies.
class CreateOrganizationCommand {
  final String legalName;
  final String tradeName;
  final String cnpj;
  final String timezone;
  final String currencyCode;
  final PlanType planType;

  /// Max vehicles quota. `null` means "derive from [planType] defaults at handler time".
  final int? maxVehicles;

  /// Max active contracts quota. `null` means "derive from [planType] defaults at handler time".
  final int? maxActiveContracts;

  final String initialAdminEmail;
  final String superAdminUserId;

  /// Operational capability flags. Defaults to [OrgCapabilities.defaults] if null.
  final OrgCapabilities? capabilities;

  /// Monthly SaaS cost in cents (INV-4). Required for ROI Guardian calculation.
  final int? toolCostCents;

  /// Default stop dwell threshold in seconds.
  final int dwellTimeSeconds;

  /// Mandatory justification recorded in system_audit_log for ORG_CREATED.
  /// Null is only valid for programmatic/test callers; the UI always requires it.
  final String? reason;

  /// Preferred billing day of month (1–28). Null = platform default.
  final int? billingDay;

  /// Primary billing/ops contact email for this org. Null = use admin email.
  final String? contactEmail;

  /// External reference ID from a 3rd-party system (CRM, ERP). Max 100 chars.
  final String? externalId;

  const CreateOrganizationCommand({
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
    this.capabilities,
    this.toolCostCents,
    this.dwellTimeSeconds = 300,
    this.reason,
    this.billingDay,
    this.contactEmail,
    this.externalId,
  });
}
