// pr_scanner: ignore-regression
//
import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/admin/org_status.dart';

/// Read model for one row in `super_admin_tenant_health_view`.
///
/// INV-4: Pure Dart — zero infrastructure dependencies.
class TenantHealthSnapshot extends Equatable {
  final String id;
  final String name;
  final String? legalName;
  final String? planType;
  final bool isActive;
  final OrgStatus? status;
  final int maxVehicles;
  final int maxActiveContracts;
  final int activeContractCount;
  final DateTime? lastTelemetryAt;
  final int openCriticalAlertCount;
  final Map<String, dynamic>? capabilities;
  final int? toolCostCents;
  final int dwellTimeSeconds;
  final int? billingDay;
  final String? contactEmail;
  final String? externalId;
  final String? organizationType;
  final DateTime? updatedAt;
  final String? cnpj;
  final DateTime? createdAt;

  const TenantHealthSnapshot({
    required this.id,
    required this.name,
    this.legalName,
    this.planType,
    required this.isActive,
    this.status,
    required this.maxVehicles,
    required this.maxActiveContracts,
    required this.activeContractCount,
    this.lastTelemetryAt,
    required this.openCriticalAlertCount,
    this.capabilities,
    this.toolCostCents,
    this.dwellTimeSeconds = 300,
    this.billingDay,
    this.contactEmail,
    this.externalId,
    this.organizationType,
    this.updatedAt,
    this.cnpj,
    this.createdAt,
  });

  factory TenantHealthSnapshot.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String?;
    final rawCaps = json['capabilities'];
    return TenantHealthSnapshot(
      id: json['id'] as String,
      name: json['name'] as String,
      legalName: json['legal_name'] as String?,
      planType: json['plan_type'] as String?,
      isActive: json['is_active'] as bool? ?? false,
      status: rawStatus != null ? OrgStatus.fromString(rawStatus) : null,
      maxVehicles: (json['max_vehicles'] as num?)?.toInt() ?? 0,
      maxActiveContracts: (json['max_active_contracts'] as num?)?.toInt() ?? 0,
      activeContractCount:
          (json['active_contract_count'] as num?)?.toInt() ?? 0,
      lastTelemetryAt: json['last_telemetry_at'] != null
          ? DateTime.parse(json['last_telemetry_at'] as String)
          : null,
      openCriticalAlertCount:
          (json['open_critical_alert_count'] as num?)?.toInt() ?? 0,
      capabilities: rawCaps is Map<String, dynamic>
          ? rawCaps
          : rawCaps is Map
          ? Map<String, dynamic>.from(rawCaps)
          : null,
      toolCostCents: (json['tool_cost_cents'] as num?)?.toInt(),
      dwellTimeSeconds: (json['dwell_time_seconds'] as num?)?.toInt() ?? 300,
      billingDay: (json['billing_day'] as num?)?.toInt(),
      contactEmail: json['contact_email'] as String?,
      externalId: json['external_id'] as String?,
      organizationType: json['organization_type'] as String?,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      cnpj: json['cnpj'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
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
    status,
    maxVehicles,
    maxActiveContracts,
    activeContractCount,
    lastTelemetryAt,
    openCriticalAlertCount,
    capabilities,
    toolCostCents,
    dwellTimeSeconds,
    billingDay,
    contactEmail,
    externalId,
    organizationType,
    updatedAt,
    cnpj,
    createdAt,
  ];
}
