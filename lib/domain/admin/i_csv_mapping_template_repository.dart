import 'package:veraprob/domain/entities/csv_mapping_template.dart';

/// Port for CSV mapping template CRUD operations.
///
/// INV-8: All operations enforce organization_id scope.
/// Concrete implementation: PostgresCsvMappingTemplateRepository.
abstract class ICsvMappingTemplateRepository {
  /// Lists templates for the authenticated org, optionally filtered by entity.
  Future<List<CsvMappingTemplate>> getTemplates({String? targetEntity});

  /// Returns the default template for an entity, or null.
  Future<CsvMappingTemplate?> getDefaultTemplate(String targetEntity);

  /// Persists a new template. Returns the created template with DB-assigned id.
  Future<CsvMappingTemplate> createTemplate(CsvMappingTemplate template);

  /// Updates an existing template (optimistic locking via version).
  /// Throws ConflictException on version mismatch.
  Future<CsvMappingTemplate> updateTemplate(CsvMappingTemplate template);

  /// Soft-deletes a template by id.
  Future<void> deleteTemplate(String templateId);
}
