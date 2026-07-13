import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/projections/forensic_ledger_view.dart';

/// Maps a raw `sla_audit_ledger_v2` row to [ForensicLedgerEntry].
/// Exposed for hermetic unit smoke (no DB) — CIA integrity / Wasm mapping.
ForensicLedgerEntry mapForensicLedgerRow(Map<String, dynamic> row) {
  final type = row['type'] as String? ?? 'UNKNOWN_EVENT';
  final operatorId = row['operator_id'] as String? ?? 'system';
  final payload = row['payload'];
  String? reason;
  if (payload is Map) {
    final r = payload['reason'];
    if (r is String) reason = r;
  }
  final occurredRaw = row['occurred_at_utc'] as String?;
  final occurredAt = occurredRaw != null
      ? DateTime.parse(occurredRaw).toUtc()
      : DateTime.now().toUtc();

  return ForensicLedgerEntry(
    decisionId: row['id'] as String? ?? '',
    actionType: type,
    actionLabel: type.replaceAll('_', ' '),
    actorId: operatorId,
    result: 'APPROVED',
    reason: reason,
    narrative: '$operatorId ${type.replaceAll('_', ' ').toLowerCase()}',
    timestamp: occurredAt,
  );
}

/// Postgres projection over [sla_audit_ledger_v2] (ledger SSOT — ponytail PR4).
class PostgresForensicLedgerProjection {
  final SupabaseClient _client;

  PostgresForensicLedgerProjection(this._client);

  /// Streams latest forensic ledger entries (org-scoped via RLS).
  Stream<List<ForensicLedgerEntry>> watchLedger({int limit = 50}) {
    return _client
        .from('sla_audit_ledger_v2')
        .stream(primaryKey: ['organization_id', 'id'])
        .order('occurred_at_utc', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(mapForensicLedgerRow).toList());
  }
}
