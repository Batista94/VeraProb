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

  // Billing / integration fields (added in Phase 10 Tier-S)
  final int? billingDay;
  final String? contactEmail;
  final String? externalId;
  final String? organizationType;

  /// Timestamp of last update — used for OCC on quota edits (CT15).
  final DateTime? updatedAt;

  /// CNPJ da organização — campo de identidade core imutável.
  final String? cnpj;

  /// Data de criação da organização — campo de identidade core imutável.
  final DateTime? createdAt;

  /// Domínios permitidos para autenticação (lista de baixo nivel de email).
  final List<String> allowedDomains;

  // CT10 — Motor Forense, Compliance, Infraestrutura

  /// Tolerância de clock drift em segundos. Padrão: 300.
  final int clockDriftToleranceS;

  /// Dias de retenção de evidências online. Padrão: 1825 (5 anos).
  final int dataRetentionDays;

  /// Limite de conexões Postgres por tenant. Padrão: 60.
  final int connectionPoolLimit;

  /// Quota de armazenamento em GB. Padrão: 100.
  final int storageQuotaGb;

  const TenantHealthView({
    required this.id,
    required this.name,
    this.legalName,
    this.planType,
    this.status,
    required this.maxVehicles,
    required this.maxActiveContracts,
    required this.activeContractCount,
    this.lastTelemetryAt,
    required this.openCriticalAlertCount,
    this.capabilities = OrgCapabilitiesViewModel.defaults,
    this.toolCostCents,
    this.dwellTimeSeconds = 300,
    this.billingDay,
    this.contactEmail,
    this.externalId,
    this.organizationType,
    this.updatedAt,
    this.cnpj,
    this.createdAt,
    this.allowedDomains = const [],
    // CT10 — Motor Forense, Compliance, Infraestrutura
    this.clockDriftToleranceS = 300,
    this.dataRetentionDays = 1825,
    this.connectionPoolLimit = 60,
    this.storageQuotaGb = 100,
  });

  /// Derived from [status] — ACTIVE orgs are operational.
  bool get isActive => status == OrgStatus.active;

  /// True when org can receive telemetry and run evaluations (ACTIVE or TRIAL).
  bool get isOperational => status?.isOperational ?? false;

  bool get isArchived => status == OrgStatus.archived;

  /// Uppercase DB key (e.g. 'ACTIVE') — pass to handlers that accept primitive status strings.
  String get statusKey => status?.dbValue ?? 'UNKNOWN';

  bool get hasCriticalAlerts => openCriticalAlertCount > 0;

  factory TenantHealthView.fromDomain(TenantHealthSnapshot snapshot) {
    return TenantHealthView(
      id: snapshot.id,
      name: snapshot.name,
      legalName: snapshot.legalName,
      planType: snapshot.planType,
      status: snapshot.status,
      maxVehicles: snapshot.maxVehicles,
      maxActiveContracts: snapshot.maxActiveContracts,
      activeContractCount: snapshot.activeContractCount,
      lastTelemetryAt: snapshot.lastTelemetryAt,
      openCriticalAlertCount: snapshot.openCriticalAlertCount,
      capabilities: OrgCapabilitiesViewModel.fromDomain(
        OrgCapabilities.fromJson(snapshot.capabilities ?? {}),
      ),
      toolCostCents: snapshot.toolCostCents,
      dwellTimeSeconds: snapshot.dwellTimeSeconds,
      billingDay: snapshot.billingDay,
      contactEmail: snapshot.contactEmail,
      externalId: snapshot.externalId,
      organizationType: snapshot.organizationType,
      updatedAt: snapshot.updatedAt,
      cnpj: snapshot.cnpj,
      createdAt: snapshot.createdAt,
      allowedDomains: snapshot.allowedDomains,
      // CT10 — Motor Forense, Compliance, Infraestrutura
      clockDriftToleranceS: snapshot.clockDriftToleranceS,
      dataRetentionDays: snapshot.dataRetentionDays,
      connectionPoolLimit: snapshot.connectionPoolLimit,
      storageQuotaGb: snapshot.storageQuotaGb,
    );
  }

  static int _parseInt(Object? val, int defaultValue) {
    if (val is num) return val.toInt();
    return defaultValue;
  }

  static int? _parseNullableInt(Object? val) {
    if (val is num) return val.toInt();
    return null;
  }

  static DateTime? _parseDateTime(Object? val) {
    if (val is String) return DateTime.parse(val);
    return null;
  }

  static List<String> _parseAllowedDomains(Object? val) {
    if (val is List) return val.cast<String>();
    return const [];
  }

  static OrgCapabilitiesViewModel _parseCapabilities(Object? raw) {
    OrgCapabilities domainCaps = OrgCapabilities.defaults;
    if (raw is Map<String, dynamic>) {
      domainCaps = OrgCapabilities.fromJson(raw);
    } else if (raw is Map) {
      domainCaps = OrgCapabilities.fromJson(Map<String, dynamic>.from(raw));
    }
    return OrgCapabilitiesViewModel.fromDomain(domainCaps);
  }

  factory TenantHealthView.fromJson(Map<String, Object?> json) {
    final rawStatus = json['status'] as String?;
    return TenantHealthView(
      id: json['id'] as String,
      name: json['name'] as String,
      legalName: json['legal_name'] as String?,
      planType: json['plan_type'] as String?,
      status: rawStatus != null ? OrgStatus.fromString(rawStatus) : null,
      maxVehicles: _parseInt(json['max_vehicles'], 0),
      maxActiveContracts: _parseInt(json['max_active_contracts'], 0),
      activeContractCount: _parseInt(json['active_contract_count'], 0),
      lastTelemetryAt: _parseDateTime(json['last_telemetry_at']),
      openCriticalAlertCount: _parseInt(json['open_critical_alert_count'], 0),
      // Map domain caps → ViewModel at the application boundary
      capabilities: _parseCapabilities(json['capabilities']),
      toolCostCents: _parseNullableInt(json['tool_cost_cents']),
      dwellTimeSeconds: _parseInt(json['dwell_time_seconds'], 300),
      billingDay: _parseNullableInt(json['billing_day']),
      contactEmail: json['contact_email'] as String?,
      externalId: json['external_id'] as String?,
      organizationType: json['organization_type'] as String?,
      updatedAt: _parseDateTime(json['updated_at']),
      cnpj: json['cnpj'] as String?,
      createdAt: _parseDateTime(json['created_at']),
      allowedDomains: _parseAllowedDomains(json['allowed_domains']),
      // CT10 — Motor Forense, Compliance, Infraestrutura
      clockDriftToleranceS: _parseInt(json['clock_drift_tolerance_s'], 300),
      dataRetentionDays: _parseInt(json['data_retention_days'], 1825),
      connectionPoolLimit: _parseInt(json['connection_pool_limit'], 60),
      storageQuotaGb: _parseInt(json['storage_quota_gb'], 100),
    );
  }
}
