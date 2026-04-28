import 'package:veraprob/application/super_admin/org_capabilities_view_model.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/tenant_health_snapshot.dart';

/// Read model for [TenantHealthSnapshot] used in the presentation layer.
///
/// **INV-4 / Lens 2 boundary enforcement:**
/// - The application-layer ViewModel is allowed to import domain types
///   internally for mapping purposes ([fromDomain], [fromJson]).
/// - The `capabilities` field is exposed as [OrgCapabilitiesViewModel] —
///   a primitive-only projection — so that `lib/features/` widgets never
///   need to import [OrgCapabilities] directly.
/// - The `status` field retains [OrgStatus] here because [TenantHealthView]
///   is itself the application-layer boundary. Features/ widgets that need
///   status-based filtering must use [TenantStatusFilter] instead of
///   comparing against [OrgStatus] directly.
class TenantHealthView {
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

  /// Capability flags as a presentation-safe ViewModel.
  /// Features/ widgets use this directly; they never hold [OrgCapabilities].
  final OrgCapabilitiesViewModel capabilities;

  final int? toolCostCents;
  final int dwellTimeSeconds;

  const TenantHealthView({
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
    this.capabilities = OrgCapabilitiesViewModel.defaults,
    this.toolCostCents,
    this.dwellTimeSeconds = 300,
  });

  bool get hasCriticalAlerts => openCriticalAlertCount > 0;

  factory TenantHealthView.fromDomain(TenantHealthSnapshot snapshot) {
    return TenantHealthView(
      id: snapshot.id,
      name: snapshot.name,
      legalName: snapshot.legalName,
      planType: snapshot.planType,
      isActive: snapshot.isActive,
      status: snapshot.status,
      maxVehicles: snapshot.maxVehicles,
      maxActiveContracts: snapshot.maxActiveContracts,
      activeContractCount: snapshot.activeContractCount,
      lastTelemetryAt: snapshot.lastTelemetryAt,
      openCriticalAlertCount: snapshot.openCriticalAlertCount,
    );
  }

  factory TenantHealthView.fromJson(Map<String, Object?> json) {
    final rawCaps = json['capabilities'];
    OrgCapabilities domainCaps = OrgCapabilities.defaults;
    if (rawCaps is Map<String, dynamic>) {
      domainCaps = OrgCapabilities.fromJson(rawCaps);
    } else if (rawCaps is Map) {
      domainCaps = OrgCapabilities.fromJson(Map<String, dynamic>.from(rawCaps));
    }

    final rawStatus = json['status'] as String?;
    return TenantHealthView(
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
      // Map domain caps → ViewModel at the application boundary
      capabilities: OrgCapabilitiesViewModel.fromDomain(domainCaps),
      toolCostCents: (json['tool_cost_cents'] as num?)?.toInt(),
      dwellTimeSeconds: (json['dwell_time_seconds'] as num?)?.toInt() ?? 300,
    );
  }
}
