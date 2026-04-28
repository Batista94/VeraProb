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
  });
}
