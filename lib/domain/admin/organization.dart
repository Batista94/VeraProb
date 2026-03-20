import 'package:equatable/equatable.dart';

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
  ];
}
