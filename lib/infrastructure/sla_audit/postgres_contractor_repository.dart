import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

class PostgresContractorRepository extends BasePostgresRepository
    implements ContractorRepository {
  PostgresContractorRepository(super.client);

  @override
  Future<List<Contractor>> findByOrganization(String organizationId) async {
    try {
      final response = await client
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
      final response = await client
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
  Future<Map<String, Contractor>> findByTaxIds(
    String organizationId,
    Set<String> taxIds,
  ) async {
    if (taxIds.isEmpty) return {};
    try {
      // Tenant-scoped fetch + Dart-side digit normalisation. tax_id is stored
      // verbatim (masked or not), so a server-side IN filter on raw strings
      // would miss formatting variants. Normalising both sides in Dart keeps
      // the match exact while staying within RLS scope (anti-oracle).
      final wanted = taxIds.map(_digits).toSet();
      final response = await client
          .from('contractors')
          .select()
          .eq('organization_id', organizationId);

      final result = <String, Contractor>{};
      for (final row in response as List) {
        final c = _fromMap(row as Map<String, dynamic>);
        final d = _digits(c.taxId ?? '');
        if (d.isNotEmpty && wanted.contains(d)) result[d] = c;
      }
      return result;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractor',
        resourceId: organizationId,
      );
    }
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'\D'), '');

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      return await executeBatchUpsertInChunks(
        rpcFunction: 'batch_upsert_contractors',
        organizationId: organizationId,
        rows: rows,
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contractor',
        resourceId: organizationId,
      );
    }
  }

  @override
  Future<void> save(Contractor contractor) async {
    try {
      await client.from('contractors').upsert({
        'id': contractor.id,
        'organization_id': contractor.organizationId,
        'name': contractor.name,
        'tax_id': contractor.taxId,
        'primary_email': contractor.primaryEmail,
        'contact_name': contractor.contactName,
        'created_at_utc': contractor.createdAtUtc.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      // Surface name-uniqueness violations as a clean domain error so the UI
      // can show a human-readable message without leaking the constraint name.
      if (e.code == '23505' &&
          (e.message.contains('uq_contractor_name_per_org') ||
              (e.details as String?)?.contains('uq_contractor_name_per_org') ==
                  true)) {
        throw const IntegrityException(
          'Já existe um contratante com este nome nesta organização.',
          field: 'name',
        );
      }
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
      await client
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
