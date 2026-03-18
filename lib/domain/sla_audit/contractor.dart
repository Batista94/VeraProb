import 'package:equatable/equatable.dart';

/// Represents a Contractor entity (e.g., Caterpillar, Vale, etc.)
/// that hires the transport services provided by the Tenant.
///
/// A Contractor is an Aggregate Root in Phase 6 to support
/// future contractor-initiated flows (e.g., self-reviewing contracts).
class Contractor extends Equatable {
  final String id;
  final String organizationId;
  final String name;
  final String? taxId;
  final String primaryEmail;
  final String contactName;
  final DateTime createdAtUtc;

  const Contractor({
    required this.id,
    required this.organizationId,
    required this.name,
    this.taxId,
    required this.primaryEmail,
    required this.contactName,
    required this.createdAtUtc,
  });

  @override
  List<Object?> get props => [
    id,
    organizationId,
    name,
    taxId,
    primaryEmail,
    contactName,
    createdAtUtc,
  ];

  Contractor copyWith({
    String? name,
    String? taxId,
    String? primaryEmail,
    String? contactName,
  }) {
    return Contractor(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      taxId: taxId ?? this.taxId,
      primaryEmail: primaryEmail ?? this.primaryEmail,
      contactName: contactName ?? this.contactName,
      createdAtUtc: createdAtUtc,
    );
  }
}
