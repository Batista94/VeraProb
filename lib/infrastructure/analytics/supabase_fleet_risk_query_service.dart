import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/analytics/fleet_risk_query_service.dart';
import 'package:veraprob/application/analytics/fleet_risk_window.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase-backed [FleetRiskQueryService]. The RPC is SECURITY DEFINER and
/// gates the JWT org server-side (returns 0 rows on mismatch, INV-26).
class SupabaseFleetRiskQueryService extends BasePostgresRepository
    implements FleetRiskQueryService {
  SupabaseFleetRiskQueryService(super.client);

  @override
  Future<List<FleetRiskWindow>> listFleetRisk({
    required String organizationId,
    int limit = 10,
  }) async {
    try {
      final rows = await client.rpc<List<dynamic>>(
        'get_fleet_risk_summary',
        params: {'p_organization_id': organizationId, 'p_limit': limit},
      );
      return rows
          .map(
            (r) =>
                FleetRiskWindow.fromJson(Map<String, dynamic>.from(r as Map)),
          )
          .toList(growable: false);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e);
    }
  }
}
