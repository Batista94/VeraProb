import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/analytics/carrier_ranking_query_service.dart';
import 'package:veraprob/application/analytics/carrier_performance_rank.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase-backed [CarrierRankingQueryService]. The RPC is SECURITY DEFINER and
/// gates the JWT org server-side (returns 0 rows on mismatch, INV-26).
class SupabaseCarrierRankingQueryService extends BasePostgresRepository
    implements CarrierRankingQueryService {
  SupabaseCarrierRankingQueryService(super.client);

  @override
  Future<List<CarrierPerformanceRank>> getRanking({
    required String organizationId,
    int limit = 20,
  }) async {
    try {
      final rows = await client.rpc<List<dynamic>>(
        'get_carrier_performance_ranking',
        params: {'p_organization_id': organizationId, 'p_limit': limit},
      );
      return rows
          .map(
            (r) => CarrierPerformanceRank.fromJson(
              Map<String, dynamic>.from(r as Map),
            ),
          )
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e);
    }
  }
}
