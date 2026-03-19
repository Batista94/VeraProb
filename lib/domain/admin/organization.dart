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

  const Organization({
    required this.id,
    required this.name,
    required this.timezone,
    required this.currencyCode,
    this.logoUrl,
    required this.isActive,
    required this.createdAt,
  });

  Organization copyWith({
    String? name,
    String? timezone,
    String? currencyCode,
    String? logoUrl,
  }) {
    return Organization(
      id: id,
      name: name ?? this.name,
      timezone: timezone ?? this.timezone,
      currencyCode: currencyCode ?? this.currencyCode,
      logoUrl: logoUrl ?? this.logoUrl,
      isActive: isActive,
      createdAt: createdAt,
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
  ];
}
