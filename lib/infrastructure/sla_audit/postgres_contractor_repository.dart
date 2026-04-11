import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

class PostgresContractorRepository
    with PostgresErrorInterceptor
    implements ContractorRepository {
  final SupabaseClient _client;

  PostgresContractorRepository(this._client);

  @override
  Future<List<Contractor>> findByOrganization(String organizationId) async {
    try {
      final response = await _client
          .from('contractors')
          .select()
          .eq('organization_id', organizationId);

      return (response as List).map((row) => _fromMap(row)).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractor',
        resourceId: organizationId,
      );
    }
  }

  @override
  Future<Contractor?> findById(String organizationId, String id) async {
    try {
      final response = await _client
          .from('contractors')
          .select()
          .eq('organization_id', organizationId)
          .eq('id', id)
          .maybeSingle();

      if (response == null) return null;
      return _fromMap(response);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractor',
        resourceId: id,
      );
    }
  }

  @override
  Future<void> save(Contractor contractor) async {
    try {
      await _client.from('contractors').upsert({
        'id': contractor.id,
        'organization_id': contractor.organizationId,
        'name': contractor.name,
        'tax_id': contractor.taxId,
        'primary_email': contractor.primaryEmail,
        'contact_name': contractor.contactName,
        'created_at_utc': contractor.createdAtUtc.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractor',
        resourceId: contractor.id,
      );
    }
  }

  @override
  Future<void> delete(String organizationId, String id) async {
    try {
      await _client
          .from('contractors')
          .delete()
          .eq('organization_id', organizationId)
          .eq('id', id);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractor',
        resourceId: id,
      );
    }
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
