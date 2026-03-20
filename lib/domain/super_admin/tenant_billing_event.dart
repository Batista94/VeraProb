import 'package:equatable/equatable.dart';

/// Immutable value object representing a single entry in `tenant_billing_events`.
///
/// INV-1: Append-only — no mutation methods.
/// INV-4: Pure Dart — zero infrastructure dependencies.
class TenantBillingEvent extends Equatable {
  final String id;
  final String? organizationId;
  final String eventType;
  final String? oldPlan;
  final String? newPlan;
  final String? changedBySuperAdminId;
  final String? reason;
  final DateTime occurredAtUtc;
  final int? oldMaxVehicles;
  final int? newMaxVehicles;
  final int? oldMaxContracts;
  final int? newMaxContracts;

  const TenantBillingEvent({
    required this.id,
    this.organizationId,
    required this.eventType,
    this.oldPlan,
    this.newPlan,
    this.changedBySuperAdminId,
    this.reason,
    required this.occurredAtUtc,
    this.oldMaxVehicles,
    this.newMaxVehicles,
    this.oldMaxContracts,
    this.newMaxContracts,
  });

  factory TenantBillingEvent.fromJson(Map<String, dynamic> json) {
    return TenantBillingEvent(
      id: json['id'] as String,
      organizationId: json['organization_id'] as String?,
      eventType: json['event_type'] as String,
      oldPlan: json['old_plan'] as String?,
      newPlan: json['new_plan'] as String?,
      changedBySuperAdminId: json['changed_by_super_admin_id'] as String?,
      reason: json['reason'] as String?,
      occurredAtUtc: DateTime.parse(json['occurred_at_utc'] as String),
      oldMaxVehicles: json['old_max_vehicles'] as int?,
      newMaxVehicles: json['new_max_vehicles'] as int?,
      oldMaxContracts: json['old_max_contracts'] as int?,
      newMaxContracts: json['new_max_contracts'] as int?,
    );
  }

  @override
  List<Object?> get props => [
    id,
    organizationId,
    eventType,
    oldPlan,
    newPlan,
    changedBySuperAdminId,
    reason,
    occurredAtUtc,
    oldMaxVehicles,
    newMaxVehicles,
    oldMaxContracts,
    newMaxContracts,
  ];
}
