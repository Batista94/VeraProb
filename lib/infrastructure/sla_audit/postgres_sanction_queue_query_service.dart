import 'package:supabase_flutter/supabase_flutter.dart';

import '../../application/sla_audit/projections/sanction_queue_item_view.dart';
import '../../application/sla_audit/projections/sanction_queue_query_service.dart';
import '../../core/config/supabase_client.dart';

/// Postgres implementation of [SanctionQueueQueryService].
class PostgresSanctionQueueQueryService implements SanctionQueueQueryService {
  final SupabaseClient _client;

  PostgresSanctionQueueQueryService([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<List<SanctionQueueItemView>> listPending({
    required String organizationId,
  }) async {
    final response = await _client
        .from('sanction_review_queue')
        .select()
        .eq('organization_id', organizationId)
        .eq('status', 'pending')
        .order('created_at', ascending: true);

    return (response as List)
        .map(
          (row) => SanctionQueueItemView.fromRow(row as Map<String, dynamic>),
        )
        .toList();
  }

  @override
  Future<int> countPending({required String organizationId}) async {
    final response = await _client.rpc(
      'get_pending_sanctions_count',
      params: {'p_org_id': organizationId},
    );
    return (response as int?) ?? 0;
  }
}
