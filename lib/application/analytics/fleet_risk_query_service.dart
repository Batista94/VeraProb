import 'package:veraprob/application/analytics/fleet_risk_window.dart';

/// Read-only query port for the fleet SLA breach-risk ranking.
///
/// Backed by the `get_fleet_risk_summary` SECURITY DEFINER RPC over
/// `execution_states` (active windows). Risk is computed server-side and
/// returned worst-first; the caller org is gated on the JWT (anti-oracle,
/// INV-26).
abstract class FleetRiskQueryService {
  Future<List<FleetRiskWindow>> listFleetRisk({
    required String organizationId,
    int limit = 10,
  });
}
