import 'sla_template.dart';

/// Repository interface for [SlaTemplate] persistence.
///
/// All queries are implicitly org-scoped — implementations must
/// enforce tenant isolation (RLS + query predicate).
abstract interface class SlaTemplateRepository {
  /// Persists a new template. Throws on name conflict within the same org.
  Future<void> save(SlaTemplate template);

  /// Returns all templates for [organizationId], ordered by name ascending.
  Future<List<SlaTemplate>> findByOrganization(String organizationId);

  /// Returns a single template by [id] within [organizationId].
  /// Returns null if not found.
  Future<SlaTemplate?> findById(String id, {required String organizationId});

  /// Deletes a template by [id] within [organizationId].
  /// No-op if the template does not exist.
  Future<void> delete(String id, {required String organizationId});
}
