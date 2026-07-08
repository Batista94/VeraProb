import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/admin/governance_audit_query_service.dart';

/// PostgreSQL implementation of [GovernanceAuditQueryService] using the
/// org-scoped, permission-gated `get_tenant_governance_log` RPC. All
/// confidentiality guards (org scope, event-type allowlist, `roles:read`
/// permission check) live server-side (INV-1, INV-2, INV-22) — this class
/// only maps the RPC's explicit typed columns to the DTO.
class PostgresGovernanceAuditQueryService
    implements GovernanceAuditQueryService {
  final SupabaseClient _client;

  PostgresGovernanceAuditQueryService(this._client);

  @override
  Future<List<GovernanceAuditEntry>> getEntries({
    int limit = 50,
    DateTime? before,
    GovernanceEventCategory? category,
    String? searchEmail,
  }) async {
    final response = await _client.rpc(
      'get_tenant_governance_log',
      params: {
        'p_limit': limit,
        'p_before': before?.toUtc().toIso8601String(),
        'p_event_category': category?.dbValue,
        'p_search_email': searchEmail,
      },
    );

    return (response as List)
        .map((row) => parseEntry(row as Map<String, dynamic>))
        .toList();
  }

  /// Pure row → DTO parsing, extracted so it's unit-testable without mocking
  /// the Supabase transport (mirrors `PostgresAccessManagementService.parseRole`).
  static GovernanceAuditEntry parseEntry(Map<String, dynamic> row) {
    return GovernanceAuditEntry(
      occurredAtUtc: DateTime.parse(row['occurred_at'] as String).toUtc(),
      eventType: row['event_type'] as String,
      actorId: row['actor_id'] as String?,
      actorEmail: row['actor_email'] as String?,
      targetUserId: row['target_user_id'] as String?,
      targetEmail: row['target_email'] as String?,
      reason: row['reason'] as String?,
    );
  }
}
