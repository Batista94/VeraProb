// pr_scanner: ignore-regression — Bloco 1D: additive batchUpsertFromCsv port
// (INV-16). No change to existing methods. Council/plan approved.
import 'operational_zone.dart';

/// Repository interface for [OperationalZone] persistence.
///
/// Pure domain interface — no Supabase or Flutter dependencies.
abstract class OperationalZoneRepository {
  /// Persists a new [OperationalZone].
  Future<void> save(OperationalZone zone);

  /// Returns the zone with [id] belonging to [organizationId], or null.
  Future<OperationalZone?> findById(
    String id, {
    required String organizationId,
  });

  /// Returns all zones for [organizationId], ordered by name.
  Future<List<OperationalZone>> findByOrganization(String organizationId);

  /// Bloco 1D: idempotent batch upsert from CSV import.
  ///
  /// [rows] are DB-shaped maps whose keys match the
  /// `batch_upsert_operational_zones` RPC recordset. Returns the number of
  /// affected rows (INV-16).
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  );
}
