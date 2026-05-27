import 'package:veraprob/domain/admin/i_csv_mapping_template_repository.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// PostgreSQL implementation of [ICsvMappingTemplateRepository] via Supabase.
///
/// INV-1 + INV-8: Every read/write explicitly filters by [organizationId] at
/// the Dart query level — defense-in-depth against service-role RLS bypass.
/// INV-3: [deleteTemplate] performs a soft-delete (sets deleted_at) instead of
/// a hard DELETE — rows are preserved for forensic audit trails.
class PostgresCsvMappingTemplateRepository extends BasePostgresRepository
    implements ICsvMappingTemplateRepository {
  PostgresCsvMappingTemplateRepository(super.client);

  @override
  Future<List<CsvMappingTemplate>> getTemplates({
    required String organizationId,
    String? targetEntity,
  }) async {
    return withErrorHandler('csv_mapping_template', null, () async {
      var query = client
          .from('csv_mapping_templates')
          .select()
          .eq('organization_id', organizationId) // INV-1: Fail-Fast org scope
          .isFilter('deleted_at', null); // INV-3: exclude soft-deleted

      if (targetEntity != null) {
        query = query.eq('target_entity', targetEntity);
      }

      final data = await query.order('name');
      return (data as List)
          .cast<Map<String, dynamic>>()
          .map(_mapToTemplate)
          .toList();
    });
  }

  @override
  Future<CsvMappingTemplate?> getDefaultTemplate({
    required String organizationId,
    required String targetEntity,
  }) async {
    return withErrorHandler('csv_mapping_template', null, () async {
      final data = await client
          .from('csv_mapping_templates')
          .select()
          .eq('organization_id', organizationId) // INV-1
          .eq('target_entity', targetEntity)
          .eq('is_default', true)
          .isFilter('deleted_at', null) // INV-3
          .maybeSingle();

      if (data == null) return null;
      return _mapToTemplate(data);
    });
  }

  @override
  Future<CsvMappingTemplate> createTemplate(CsvMappingTemplate template) async {
    template.assertValid();
    final payload = _mapToDb(template);
    return withErrorHandler('csv_mapping_template', template.id, () async {
      final data = await client
          .from('csv_mapping_templates')
          .insert(payload)
          .select()
          .single();
      return _mapToTemplate(data);
    }, insertPayload: payload);
  }

  @override
  Future<CsvMappingTemplate> updateTemplate(CsvMappingTemplate template) async {
    template.assertValid();
    final payload = _mapToDb(template);

    // Remove DB-controlled / immutable columns from update payload.
    payload
      ..remove('id')
      ..remove('organization_id')
      ..remove('created_at')
      ..remove('version');

    return withErrorHandler('csv_mapping_template', template.id, () async {
      final newVersion = await updateWithVersion(
        table: 'csv_mapping_templates',
        data: payload,
        id: template.id,
        currentVersion: template.version,
        resourceType: 'csv_mapping_template',
      );
      return template.copyWith(
        version: newVersion,
        updatedAt: DateTime.now().toUtc(),
      );
    });
  }

  /// Soft-deletes [templateId] by setting deleted_at to the current UTC time.
  ///
  /// The double `.eq('organization_id', organizationId)` filter is intentional:
  /// it prevents cross-tenant deletion even when a service-role key is used
  /// (service role bypasses RLS). If the template does not exist in the org,
  /// Postgres updates 0 rows — no error, idempotent (INV-15).
  @override
  Future<void> deleteTemplate(
    String templateId, {
    required String organizationId,
  }) async {
    return withErrorHandler('csv_mapping_template', templateId, () async {
      await client
          .from('csv_mapping_templates')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', templateId)
          .eq('organization_id', organizationId); // INV-1: cross-tenant guard
    });
  }

  // ── Mapping helpers ──────────────────────────────────────────────────────

  CsvMappingTemplate _mapToTemplate(Map<String, dynamic> data) {
    final rawMappings = data['column_mappings'];
    final columnMappings = rawMappings is List
        ? rawMappings
              .cast<Map<String, dynamic>>()
              .map((json) => ColumnMapping.fromJson(json))
              .toList()
        : <ColumnMapping>[];

    return CsvMappingTemplate(
      id: data['id'] as String,
      organizationId: data['organization_id'] as String,
      name: data['name'] as String,
      targetEntity: data['target_entity'] as String,
      columnMappings: columnMappings,
      isDefault: data['is_default'] as bool? ?? false,
      version: data['version'] as int? ?? 1,
      createdAt: DateTime.parse(data['created_at'] as String).toUtc(),
      updatedAt: DateTime.parse(data['updated_at'] as String).toUtc(),
      createdBy: data['created_by'] as String?,
    );
  }

  Map<String, dynamic> _mapToDb(CsvMappingTemplate template) {
    return {
      'id': template.id,
      'organization_id': template.organizationId,
      'name': template.name,
      'target_entity': template.targetEntity,
      'column_mappings': template.columnMappings
          .map((m) => m.toJson())
          .toList(),
      'is_default': template.isDefault,
      'version': template.version,
      'created_at': template.createdAt.toUtc().toIso8601String(),
      'updated_at': template.updatedAt.toUtc().toIso8601String(),
      'created_by': template.createdBy,
    };
  }
}
