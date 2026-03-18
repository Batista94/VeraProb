import 'shadow_mode_simulation.dart';

/// Port (interface) for persisting and querying [ShadowModeSimulation] records.
///
/// All queries are scoped by [organizationId] (INV-6).
abstract class ShadowModeRepository {
  /// Persists a new [ShadowModeSimulation].
  Future<void> save(ShadowModeSimulation simulation);

  /// Returns all simulations for the organization, ordered by [generatedAtUtc] DESC.
  Future<List<ShadowModeSimulation>> findByOrganization({
    required String organizationId,
    int limit = 10,
  });

  /// Returns the simulation with [id] scoped to [organizationId], or null.
  Future<ShadowModeSimulation?> findById({
    required String id,
    required String organizationId,
  });
}
