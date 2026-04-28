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
  });
}
