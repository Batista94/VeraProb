import 'service_manifest.dart';

/// Repository interface for [ServiceManifest] persistence.
///
/// All queries are implicitly org-scoped — implementations must
/// enforce tenant isolation (RLS + query predicate).
abstract interface class ServiceManifestRepository {
  /// Persists a new or updated service manifest.
  Future<void> save(ServiceManifest manifest);

  /// Returns all manifests for a given [contractId] within [organizationId].
  Future<List<ServiceManifest>> findByContract(
    String contractId, {
    required String organizationId,
  });

  /// Returns a single manifest by [id] within [organizationId].
  /// Returns null if not found.
  Future<ServiceManifest?> findById(
    String id, {
    required String organizationId,
  });

  /// Deletes a manifest by [id] within [organizationId].
  /// No-op if the manifest does not exist.
  Future<void> delete(String id, {required String organizationId});
}
