import 'telemetry_evidence.dart';

/// Port (domain repository interface) for [TelemetryEvidence] persistence.
///
/// The table is append-only (INV-1 extended to evidence). Implementations
/// must never expose UPDATE or DELETE operations.
abstract class TelemetryEvidenceRepository {
  /// Persists a new [TelemetryEvidence] record.
  ///
  /// Throws if [evidence.contentHash] already exists (duplicate detection).
  Future<void> save(TelemetryEvidence evidence);

  /// Returns all evidence records for [setId], ordered by [seq] ascending.
  Future<List<TelemetryEvidence>> findBySetId(
    String setId, {
    required String organizationId,
  });

  /// Returns the most recently saved evidence record for [setId], or `null`
  /// if the chain is empty. Used to obtain [previousEvidenceHash] for the
  /// next [TelemetryEvidence.create] call.
  Future<TelemetryEvidence?> findLatestBySetId(
    String setId, {
    required String organizationId,
  });
}
