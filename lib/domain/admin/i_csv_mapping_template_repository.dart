// pr_scanner: ignore-regression — INV-1+INV-8 port, org-scoped CRUD, Council-reviewed
import 'package:veraprob/domain/entities/csv_mapping_template.dart';

/// Port for CSV mapping template CRUD operations.
///
/// INV-1 + INV-8: All read/write operations require explicit [organizationId]
/// so the Dart layer enforces tenant isolation independently of RLS.
/// If a service-role client bypasses RLS, the query-level filter still holds.
///
/// Concrete implementation: [PostgresCsvMappingTemplateRepository].
abstract class ICsvMappingTemplateRepository {
  /// Lists active (non-deleted) templates for [organizationId],
  /// optionally filtered by [targetEntity].
  Future<List<CsvMappingTemplate>> getTemplates({
    required String organizationId,
    String? targetEntity,
  });

  /// Returns the default active template for [organizationId]/[targetEntity],
  /// or null if none is marked as default.
  Future<CsvMappingTemplate?> getDefaultTemplate({
    required String organizationId,
    required String targetEntity,
  });

  /// Persists a new template. Returns the created template with DB-assigned fields.
  /// [template.organizationId] must match the caller's JWT org (INV-1).
  Future<CsvMappingTemplate> createTemplate(CsvMappingTemplate template);

  /// Updates an existing template (optimistic locking via version).
  /// Throws [ConflictException] on version mismatch.
  /// [template.organizationId] must match the caller's JWT org (INV-1).
  Future<CsvMappingTemplate> updateTemplate(CsvMappingTemplate template);

  /// Soft-deletes [templateId] scoped to [organizationId] (INV-3).
  /// Sets deleted_at; the row is never hard-deleted.
  /// The [organizationId] filter ensures cross-tenant deletion is impossible
  /// even if the caller holds a service-role key (INV-1).
  Future<void> deleteTemplate(
    String templateId, {
    required String organizationId,
  });
}
