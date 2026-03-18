import 'canonical_fact.dart';
import 'ingestion_integrity_flag.dart';

/// Repository interface for [CanonicalFact] records.
///
/// All reads are scoped by [organizationId] (INV-6).
/// No write method is exposed here — writes are performed by the
/// Edge Function Adapters via the Supabase service role.
abstract class CanonicalFactRepository {
  /// Returns all [CanonicalFact] records for the given [assetId] within the
  /// specified time window, ordered by [gpsTimestamp] ascending (INV-12).
  ///
  /// Only facts eligible for evaluation are returned by default.
  /// Pass [includeAllFlags] = true to include integrity-flagged facts.
  Future<List<CanonicalFact>> findByAssetInWindow({
    required String assetId,
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
    bool includeAllFlags = false,
  });

  /// Returns all unprocessed [CanonicalFact] records for the given [deviceId],
  /// ordered by [gpsTimestamp] ascending.
  ///
  /// Used by the [TelemetryIngestionPipeline] for batch processing.
  Future<List<CanonicalFact>> findByDeviceChronological({
    required String deviceId,
    required String organizationId,
    DateTime? sinceUtc,
  });

  /// Saves a [CanonicalFact] to the repository (for in-memory/test use).
  Future<void> save(CanonicalFact fact);

  /// Returns facts grouped by [IngestionIntegrityFlag] for audit purposes.
  Future<Map<IngestionIntegrityFlag, int>> countByIntegrityFlag({
    required String organizationId,
    required DateTime fromUtc,
    required DateTime toUtc,
  });
}
