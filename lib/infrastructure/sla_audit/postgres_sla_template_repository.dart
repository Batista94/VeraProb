import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import '../../domain/sla_audit/sla_penalties.dart';
import '../../domain/sla_audit/sla_template.dart';
import '../../domain/sla_audit/sla_template_repository.dart';

/// Postgres implementation of [SlaTemplateRepository].
///
/// RLS guarantees tenant isolation: all queries are scoped to the
/// authenticated user's organization via JWT `organization_id`.
class PostgresSlaTemplateRepository implements SlaTemplateRepository {
  final SupabaseClient _client;

  PostgresSlaTemplateRepository([SupabaseClient? client])
      : _client = client ?? supabase;

  @override
  Future<void> save(SlaTemplate template) async {
    await _client.from('sla_templates').upsert({
      'id': template.id,
      'organization_id': template.organizationId,
      'name': template.name,
      'description': template.description,
      'penalties_payload': template.penalties.toJson(),
      'created_at': template.createdAt.toIso8601String(),
    });
  }

  @override
  Future<List<SlaTemplate>> findByOrganization(String organizationId) async {
    final List<Map<String, dynamic>> rows = await _client
        .from('sla_templates')
        .select()
        .eq('organization_id', organizationId)
        .order('name', ascending: true);

    return rows.map(_mapToEntity).toList();
  }

  @override
  Future<void> delete(String id, {required String organizationId}) async {
    await _client
        .from('sla_templates')
        .delete()
        .eq('id', id)
        .eq('organization_id', organizationId);
  }

  SlaTemplate _mapToEntity(Map<String, dynamic> row) {
    final payload = row['penalties_payload'] as Map<String, dynamic>;
    final penalties = SLAPenalties.fromJson(payload);

    return SlaTemplate.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      penalties: penalties,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }
}
