import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/sla_template.dart';
import 'package:veraprob/domain/sla_audit/sla_template_repository.dart';
import 'package:veraprob/domain/sla_audit/transport_vertical.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// Postgres implementation of [SlaTemplateRepository].
///
/// RLS guarantees tenant isolation: all queries are scoped to the
/// authenticated user's organization via JWT `organization_id`.
class PostgresSlaTemplateRepository
    with PostgresErrorInterceptor
    implements SlaTemplateRepository {
  final SupabaseClient _client;

  PostgresSlaTemplateRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<void> save(SlaTemplate template) async {
    try {
      await _client.from('sla_templates').upsert({
        'id': template.id,
        'organization_id': template.organizationId,
        'name': template.name,
        'description': template.description,
        'vertical': template.vertical?.toJson(),
        'penalties_payload': template.penalties.toJson(),
        'created_at': template.createdAt.toIso8601String(),
      });
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'sla_template');
    }
  }

  @override
  Future<List<SlaTemplate>> findByOrganization(String organizationId) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('sla_templates')
          .select()
          .eq('organization_id', organizationId)
          .order('name', ascending: true);

      return rows.map(_mapToEntity).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'sla_template');
    }
  }

  @override
  Future<SlaTemplate?> findById(
    String id, {
    required String organizationId,
  }) async {
    try {
      final List<Map<String, dynamic>> rows = await _client
          .from('sla_templates')
          .select()
          .eq('id', id)
          .eq('organization_id', organizationId)
          .limit(1);

      if (rows.isEmpty) return null;
      return _mapToEntity(rows.first);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'sla_template');
    }
  }

  @override
  Future<void> delete(String id, {required String organizationId}) async {
    try {
      await _client
          .from('sla_templates')
          .delete()
          .eq('id', id)
          .eq('organization_id', organizationId);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'sla_template');
    }
  }

  SlaTemplate _mapToEntity(Map<String, dynamic> row) {
    final payload = row['penalties_payload'] as Map<String, dynamic>;
    final penalties = SLAPenalties.fromJson(payload);

    final verticalRaw = row['vertical'] as String?;

    return SlaTemplate.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      name: row['name'] as String,
      description: row['description'] as String?,
      vertical: verticalRaw != null
          ? TransportVertical.fromJson(verticalRaw)
          : null,
      penalties: penalties,
      createdAt: DateTime.parse(row['created_at'] as String).toUtc(),
    );
  }
}
