import 'package:equatable/equatable.dart';
import 'package:veraprob/domain/admin/org_capabilities.dart';

/// Represents an organization (tenant) in the veraprob system.
class Organization extends Equatable {
  final String id;
  final String name;
  final String timezone;
  final String currencyCode;
  final String? logoUrl;
  final bool isActive;
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

  const Organization({
    required this.id,
    required this.name,
    required this.timezone,
    required this.currencyCode,
    this.logoUrl,
    required this.isActive,
    required this.createdAt,
    this.legalName,
    this.cnpj,
    this.planType,
    this.maxVehicles,
    this.maxActiveContracts,
    this.organizationType,
    this.capabilities = OrgCapabilities.defaults,
  });

  Organization copyWith({
    String? name,
    String? timezone,
    String? currencyCode,
    String? logoUrl,
    String? legalName,
    String? cnpj,
    String? planType,
    int? maxVehicles,
    int? maxActiveContracts,
    String? organizationType,
    OrgCapabilities? capabilities,
  }) {
    return Organization(
      id: id,
      name: name ?? this.name,
      timezone: timezone ?? this.timezone,
      currencyCode: currencyCode ?? this.currencyCode,
      logoUrl: logoUrl ?? this.logoUrl,
      isActive: isActive,
      createdAt: createdAt,
      legalName: legalName ?? this.legalName,
      cnpj: cnpj ?? this.cnpj,
      planType: planType ?? this.planType,
      maxVehicles: maxVehicles ?? this.maxVehicles,
      maxActiveContracts: maxActiveContracts ?? this.maxActiveContracts,
      organizationType: organizationType ?? this.organizationType,
      capabilities: capabilities ?? this.capabilities,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    timezone,
    currencyCode,
    logoUrl,
    isActive,
    createdAt,
    legalName,
    cnpj,
    planType,
    maxVehicles,
    maxActiveContracts,
    organizationType,
    capabilities,
  ];
}
