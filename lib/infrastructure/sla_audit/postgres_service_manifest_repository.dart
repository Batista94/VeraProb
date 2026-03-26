import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import '../../domain/sla_audit/service_manifest.dart';
import '../../domain/sla_audit/service_manifest_repository.dart';
import '../../domain/sla_audit/sla_penalties.dart';
import '../../domain/sla_audit/transport_vertical.dart';

/// Postgres implementation of [ServiceManifestRepository].
///
/// RLS guarantees tenant isolation: all queries are scoped to the
/// authenticated user's organization via JWT `organization_id`.
class PostgresServiceManifestRepository implements ServiceManifestRepository {
  final SupabaseClient _client;

  PostgresServiceManifestRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<void> save(ServiceManifest manifest) async {
    await _client.from('service_manifests').upsert({
      'id': manifest.id,
      'organization_id': manifest.organizationId,
      'contract_id': manifest.contractId,
      'name': manifest.name,
      'description': manifest.description,
      'sla_template_id': manifest.slaTemplateId,
      'vertical': manifest.vertical.toJson(),
      'penalties_payload': manifest.penalties.toJson(),
      'created_at': manifest.createdAtUtc.toIso8601String(),
    });
  }

  @override
  Future<List<ServiceManifest>> findByContract(
    String contractId, {
    required String organizationId,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('service_manifests')
        .select()
        .eq('organization_id', organizationId)
        .eq('contract_id', contractId)
        .order('name', ascending: true);

    return rows.map(_mapToEntity).toList();
  }

  @override
  Future<ServiceManifest?> findById(
    String id, {
    required String organizationId,
  }) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('service_manifests')
        .select()
        .eq('id', id)
        .eq('organization_id', organizationId)
        .limit(1);

    if (rows.isEmpty) return null;
    return _mapToEntity(rows.first);
  }

  @override
  Future<void> delete(String id, {required String organizationId}) async {
    await _client
        .from('service_manifests')
        .delete()
        .eq('id', id)
        .eq('organization_id', organizationId);
  }

  ServiceManifest _mapToEntity(Map<String, dynamic> row) {
    final payload = row['penalties_payload'] as Map<String, dynamic>;
    final penalties = SLAPenalties.fromJson(payload);

    return ServiceManifest.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      contractId: row['contract_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      slaTemplateId: row['sla_template_id'] as String?,
      vertical: TransportVertical.fromJson(row['vertical'] as String?),
      penalties: penalties,
      createdAtUtc: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }
}
