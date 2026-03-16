import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/sla_audit/contractor.dart';
import '../../domain/sla_audit/contractor_repository.dart';

class PostgresContractorRepository implements ContractorRepository {
  final SupabaseClient _client;

  PostgresContractorRepository(this._client);

  @override
  Future<List<Contractor>> findByOrganization(String organizationId) async {
    final response = await _client
        .from('contractors')
        .select()
        .eq('organization_id', organizationId);

    return (response as List).map((row) => _fromMap(row)).toList();
  }

  @override
  Future<Contractor?> findById(String organizationId, String id) async {
    final response = await _client
        .from('contractors')
        .select()
        .eq('organization_id', organizationId)
        .eq('id', id)
        .maybeSingle();

    if (response == null) return null;
    return _fromMap(response);
  }

  @override
  Future<void> save(Contractor contractor) async {
    await _client.from('contractors').upsert({
      'id': contractor.id,
      'organization_id': contractor.organizationId,
      'name': contractor.name,
      'tax_id': contractor.taxId,
      'primary_email': contractor.primaryEmail,
      'contact_name': contractor.contactName,
      'created_at_utc': contractor.createdAtUtc.toIso8601String(),
    });
  }

  Contractor _fromMap(Map<String, dynamic> map) {
    return Contractor(
      id: map['id'] as String,
      organizationId: map['organization_id'] as String,
      name: map['name'] as String,
      taxId: map['tax_id'] as String?,
      primaryEmail: map['primary_email'] as String,
      contactName: map['contact_name'] as String,
      createdAtUtc: DateTime.parse(map['created_at_utc'] as String),
    );
  }
}
