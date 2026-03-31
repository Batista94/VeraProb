import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/sla_audit/local_fact_queue/handshake_result.dart';
import '../../domain/sla_audit/local_fact_queue/sync_handshake_service.dart';

/// Supabase implementation of [SyncHandshakeService].
///
/// Calls the security-definer RPC [get_missed_facts] which returns
/// fact IDs published after [clientLastSeenAtUtc] for the given tenant.
///
/// **INV-1:** [organizationId] is passed explicitly — never derived from
///            client-side state.
/// **INV-9:** All timestamps are UTC.
class SupabaseSyncHandshakeService implements SyncHandshakeService {
  final SupabaseClient _client;

  SupabaseSyncHandshakeService(this._client);

  @override
  Future<HandshakeResult> performHandshake({
    required String organizationId,
    required DateTime clientLastSeenAtUtc,
  }) async {
    final rows =
        await _client.rpc(
              'get_missed_facts',
              params: {
                'p_org_id': organizationId,
                'p_after_utc': clientLastSeenAtUtc.toIso8601String(),
              },
            )
            as List<dynamic>;

    final missingFactIds = rows
        .cast<Map<String, dynamic>>()
        .map((r) => r['id'] as String)
        .toList();

    final lastServerAt = rows.isEmpty
        ? clientLastSeenAtUtc
        : DateTime.parse(
            (rows.cast<Map<String, dynamic>>().last)['received_at'] as String,
          ).toUtc();

    return HandshakeResult(
      lastServerFactReceivedAt: lastServerAt,
      missingFactIds: missingFactIds,
    );
  }
}
