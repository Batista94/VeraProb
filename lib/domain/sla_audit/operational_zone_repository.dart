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
}
