import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';

/// Read model for [TenantHealthSnapshot] used in presentation layer.
class TenantHealthView {
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

  const TenantHealthView({
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

  bool get hasCriticalAlerts => openCriticalAlertCount > 0;

  factory TenantHealthView.fromDomain(TenantHealthSnapshot snapshot) {
    return TenantHealthView(
      id: snapshot.id,
      name: snapshot.name,
      legalName: snapshot.legalName,
      planType: snapshot.planType,
      isActive: snapshot.isActive,
      maxVehicles: snapshot.maxVehicles,
      maxActiveContracts: snapshot.maxActiveContracts,
      activeContractCount: snapshot.activeContractCount,
      lastTelemetryAt: snapshot.lastTelemetryAt,
      openCriticalAlertCount: snapshot.openCriticalAlertCount,
    );
  }

  factory TenantHealthView.fromJson(Map<String, Object?> json) {
    return TenantHealthView(
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
}
