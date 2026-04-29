import 'package:veraprob/domain/admin/org_capabilities.dart';

/// Immutable command DTO for updating an existing tenant's plan, quota limits,
/// and operational configuration.
///
/// Contains ZERO logic — pure information transfer object.
/// INV-4: Pure Dart — zero infrastructure dependencies.
class UpdateOrganizationQuotaCommand {
  /// UUID of the organization to update.
  final String organizationId;

  /// New plan type: 'starter', 'professional', or 'enterprise'.
  final String newPlanType;

  /// New max vehicles. `null` means unlimited (enterprise tier).
  final int? newMaxVehicles;

  /// New max active contracts. `null` means unlimited (enterprise tier).
  final int? newMaxActiveContracts;

  /// UUID of the SuperAdmin performing this change (audit trail).
  final String superAdminUserId;

  /// Optional reason recorded in the billing factEvent.
  final String? reason;

  /// Session ID for tenant validation.
  final String sessionId;

  /// Operational capability flags. `null` = keep existing in DB (COALESCE).
  final OrgCapabilities? capabilities;

  /// Monthly SaaS cost in cents (INV-4). Required — null rejected by handler.
  final int? toolCostCents;

  /// Default stop dwell threshold in seconds. `null` = keep existing in DB.
  final int? dwellTimeSeconds;

  /// Preferred billing day of month (1-28).
  final int? billingDay;

  /// Primary billing/ops contact email for this org.
  final String? contactEmail;

  /// External reference ID from a 3rd-party system (CRM, ERP). Max 100 chars.
  final String? externalId;

  /// Classification of the organization's business (e.g. CARGO, PASSENGER, URBAN_LOGISTICS).
  final String? organizationType;

  const UpdateOrganizationQuotaCommand({
    required this.organizationId,
    required this.newPlanType,
    this.newMaxVehicles,
    this.newMaxActiveContracts,
    required this.superAdminUserId,
    this.reason,
    required this.sessionId,
    this.capabilities,
    this.toolCostCents,
    this.dwellTimeSeconds,
    this.billingDay,
    this.contactEmail,
    this.externalId,
    this.organizationType,
  });
}
