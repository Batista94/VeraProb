import 'package:veraprob/domain/sla_audit/contractor.dart';

/// Flat read model for [Contractor] used in presentation layer.
class ContractorView {
  final String id;
  final String organizationId;
  final String name;
  final String? taxId;
  final String primaryEmail;
  final String contactName;
  final DateTime createdAtUtc;

  const ContractorView({
    required this.id,
    required this.organizationId,
    required this.name,
    this.taxId,
    required this.primaryEmail,
    required this.contactName,
    required this.createdAtUtc,
  });

  factory ContractorView.fromDomain(Contractor contractor) {
    return ContractorView(
      id: contractor.id,
      organizationId: contractor.organizationId,
      name: contractor.name,
      taxId: contractor.taxId,
      primaryEmail: contractor.primaryEmail,
      contactName: contractor.contactName,
      createdAtUtc: contractor.createdAtUtc,
    );
  }

  factory ContractorView.fromRow(Map<String, Object?> row) {
    return ContractorView(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      name: row['name'] as String,
      taxId: row['tax_id'] as String?,
      primaryEmail: row['primary_email'] as String,
      contactName: row['contact_name'] as String,
      createdAtUtc: DateTime.parse(row['created_at'] as String),
    );
  }
}
