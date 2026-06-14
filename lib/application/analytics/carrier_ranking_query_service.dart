import 'package:veraprob/application/analytics/carrier_performance_rank.dart';

/// Read-only query port for the carrier performance ranking.
///
/// Backed by the `get_carrier_performance_ranking` SECURITY DEFINER RPC: the
/// caller org is gated server-side on the JWT `app_metadata.org_id` and a
/// mismatch yields an empty list (anti-oracle INV-26). Worst performers first.
abstract class CarrierRankingQueryService {
  Future<List<CarrierPerformanceRank>> getRanking({
    required String organizationId,
    int limit = 20,
  });
}
