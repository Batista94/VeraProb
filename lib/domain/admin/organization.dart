// pr_scanner: ignore-regression
//
import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';
import 'package:veraprob/domain/admin/org_status.dart';

/// Represents an organization (tenant) in the veraprob system.
class Organization extends Equatable {
  final String id;
  final String name;
  final String timezone;
  final String currencyCode;
  final String? logoUrl;
  final OrgStatus status;
  final DateTime createdAt;

  // Phase 9.2 SuperAdmin fields (nullable — added via migration, may be absent in legacy rows)
  final String? legalName;
  final String? cnpj;
  final String? planType;
  final int? maxVehicles;
  final int? maxActiveContracts;

  // Phase 10: cosmetic label + operational capability flags (INV-14: agnostic flags, not enum)
  final String? organizationType;
  final OrgCapabilities capabilities;

  // Phase 10.2: billing & contact fields
  final int? billingDay;
  final String? contactEmail;
  final String? externalId;

  // Phase 10.3: operational business defaults (INV-14 — config, not hard limit)
  /// Stop dwell threshold in seconds. Org Admin can override this after onboarding.
  final int dwellTimeSeconds;

  // Phase 10: email domain whitelist (SSO routing, identity injection prevention)
  final List<String> allowedDomains;

  const Organization({
    required this.id,
    required this.name,
    required this.timezone,
    required this.currencyCode,
    this.logoUrl,
    required this.status,
    required this.createdAt,
    this.legalName,
    this.cnpj,
    this.planType,
    this.maxVehicles,
    this.maxActiveContracts,
    this.organizationType,
    this.capabilities = OrgCapabilities.defaults,
    this.billingDay,
    this.contactEmail,
    this.externalId,
    this.dwellTimeSeconds = 300,
    this.allowedDomains = const [],
  });

  /// Retro-compatible getter: true only when status is ACTIVE.
  bool get isActive => status == OrgStatus.active;

  /// Whether the org can operate (receive telemetry, run evaluations).
  bool get isOperational => status.isOperational;

  Organization copyWith({
    String? name,
    String? timezone,
    String? currencyCode,
    String? logoUrl,
    OrgStatus? status,
    String? legalName,
    String? cnpj,
    String? planType,
    int? maxVehicles,
    int? maxActiveContracts,
    String? organizationType,
    OrgCapabilities? capabilities,
    int? billingDay,
    String? contactEmail,
    String? externalId,
    int? dwellTimeSeconds,
    List<String>? allowedDomains,
  }) {
    return Organization(
      id: id,
      name: name ?? this.name,
      timezone: timezone ?? this.timezone,
      currencyCode: currencyCode ?? this.currencyCode,
      logoUrl: logoUrl ?? this.logoUrl,
      status: status ?? this.status,
      createdAt: createdAt,
      legalName: legalName ?? this.legalName,
      cnpj: cnpj ?? this.cnpj,
      planType: planType ?? this.planType,
      maxVehicles: maxVehicles ?? this.maxVehicles,
      maxActiveContracts: maxActiveContracts ?? this.maxActiveContracts,
      organizationType: organizationType ?? this.organizationType,
      capabilities: capabilities ?? this.capabilities,
      billingDay: billingDay ?? this.billingDay,
      contactEmail: contactEmail ?? this.contactEmail,
      externalId: externalId ?? this.externalId,
      dwellTimeSeconds: dwellTimeSeconds ?? this.dwellTimeSeconds,
      allowedDomains: allowedDomains ?? this.allowedDomains,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    timezone,
    currencyCode,
    logoUrl,
    status,
    createdAt,
    legalName,
    cnpj,
    planType,
    maxVehicles,
    maxActiveContracts,
    organizationType,
    capabilities,
    billingDay,
    contactEmail,
    externalId,
    dwellTimeSeconds,
    allowedDomains,
  ];
}
