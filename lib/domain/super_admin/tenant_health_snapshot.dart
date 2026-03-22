import 'package:equatable/equatable.dart';

/// Read model for one row in `super_admin_tenant_health_view`.
///
/// INV-4: Pure Dart — zero infrastructure dependencies.
class TenantHealthSnapshot extends Equatable {
  final String id;
  final String name;
  final String? legalName;
  final String? planType;
  final bool isActive;
  final int maxVehicles;
  final int maxActiveContracts;
  final int activeContractCount;
  final DateTime? lastTelemetryAt;
  final int openCriticalAlertCount;

  const TenantHealthSnapshot({
    required this.id,
    required this.name,
    this.legalName,
    this.planType,
    required this.isActive,
    required this.maxVehicles,
    required this.maxActiveContracts,
    required this.activeContractCount,
    this.lastTelemetryAt,
    required this.openCriticalAlertCount,
  });

  factory TenantHealthSnapshot.fromJson(Map<String, dynamic> json) {
    return TenantHealthSnapshot(
      id: json['id'] as String,
      name: json['name'] as String,
      legalName: json['legal_name'] as String?,
      planType: json['plan_type'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      maxVehicles: (json['max_vehicles'] as num?)?.toInt() ?? 0,
      maxActiveContracts: (json['max_active_contracts'] as num?)?.toInt() ?? 0,
      activeContractCount:
          (json['active_contract_count'] as num?)?.toInt() ?? 0,
      lastTelemetryAt: json['last_telemetry_at'] != null
          ? DateTime.parse(json['last_telemetry_at'] as String)
          : null,
      openCriticalAlertCount:
          (json['open_critical_alert_count'] as num?)?.toInt() ?? 0,
    );
  }

  bool get hasCriticalAlerts => openCriticalAlertCount > 0;

  @override
  List<Object?> get props => [
    id,
    name,
    legalName,
    planType,
    isActive,
    maxVehicles,
    maxActiveContracts,
    activeContractCount,
    lastTelemetryAt,
    openCriticalAlertCount,
  ];
}
