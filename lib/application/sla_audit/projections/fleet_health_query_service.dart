import 'fleet_health_view.dart';

/// Abstract query service for the Fleet Health projection.
///
/// Implementations call the `get_fleet_health_status` RPC and map results
/// to [FleetHealthView]. Scoped per [organizationId] (INV-1).
abstract class FleetHealthQueryService {
  /// Returns the current fleet health snapshot for [organizationId].
  ///
  /// [delayedSec] and [offlineSec] allow the caller to adjust sensitivity
  /// thresholds without a migration. Defaults: 900s (15 min), 3600s (1h).
  Future<FleetHealthView> getFleetHealth({
    required String organizationId,
    int delayedSec = 900,
    int offlineSec = 3600,
  });
}
