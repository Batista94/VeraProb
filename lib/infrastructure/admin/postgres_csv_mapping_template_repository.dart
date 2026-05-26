import 'package:veraprob/domain/admin/i_csv_mapping_template_repository.dart';
import 'package:veraprob/domain/entities/column_mapping.dart';
import 'package:veraprob/domain/entities/csv_mapping_template.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// PostgreSQL implementation of [ICsvMappingTemplateRepository] via Supabase.
///
/// Scoped to organizations to ensure strict tenant isolation (INV-1, INV-22).
/// Implements optimistic locking on update via [BasePostgresRepository.updateWithVersion] (INV-10).
class PostgresCsvMappingTemplateRepository extends BasePostgresRepository
    implements ICsvMappingTemplateRepository {
  PostgresCsvMappingTemplateRepository(super.client);

  @override
  Future<List<CsvMappingTemplate>> getTemplates({String? targetEntity}) async {
    return withErrorHandler('csv_mapping_template', null, () async {
      var query = client.from('csv_mapping_templates').select();
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
  Future<CsvMappingTemplate?> getDefaultTemplate(String targetEntity) async {
    return withErrorHandler('csv_mapping_template', null, () async {
      final data = await client
          .from('csv_mapping_templates')
          .select()
          .eq('target_entity', targetEntity)
          .eq('is_default', true)
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

    // Remove database-controlled/immutable columns for updates
    payload.remove('id');
    payload.remove('organization_id');
    payload.remove('created_at');
    payload.remove('version');

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

  @override
  Future<void> deleteTemplate(String templateId) async {
    return withErrorHandler('csv_mapping_template', templateId, () async {
      await client.from('csv_mapping_templates').delete().eq('id', templateId);
    });
  }

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
