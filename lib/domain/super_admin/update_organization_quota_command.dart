/// Immutable command DTO for updating an existing tenant's plan and quota limits.
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

  const UpdateOrganizationQuotaCommand({
    required this.organizationId,
    required this.newPlanType,
    this.newMaxVehicles,
    this.newMaxActiveContracts,
    required this.superAdminUserId,
    this.reason,
  });
}
