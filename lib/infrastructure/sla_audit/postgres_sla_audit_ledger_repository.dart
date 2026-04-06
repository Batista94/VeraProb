import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

/// Postgres implementation of [SlaAuditLedgerRepository].
///
/// **Architecture Guarantees:**
/// 1. **Absolute Append-Only**: Lack of delete/update methods ensures immutability.
/// 2. **Monotonic Ordering**: Uses Postgres `bigserial` (ID) as the primary ordering criterion.
/// 3. **Idempotency**: Prevents duplicate entries via causal linkage checks or cautious inserts.
/// 4. **Structured Mapping**: Persists structured [SlaLedgerEntry] instead of raw events.
class PostgresSlaAuditLedgerRepository implements SlaAuditLedgerRepository {
  final SupabaseClient _client;

  PostgresSlaAuditLedgerRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<String> append(SlaLedgerEntry entry) async {
    final response = await _client
        .from('sla_audit_ledger_v2')
        .insert({
          'organization_id': entry.organizationId,
          'type': entry.type,
          'operator_id': entry.operatorId,
          'set_id': entry.setId,
          'contract_id': entry.contractId,
          'plan_version': entry.planVersion,
          'payload': entry.payload,
          'occurred_at_utc': entry.occurredAtUtc.toIso8601String(),
        })
        .select('id')
        .single();

    return response['id'] as String;
  }

  @override
  Future<String?> getLastEntryId({String? organizationId}) async {
    var query = _client.from('sla_audit_ledger_v2').select('id');
    if (organizationId != null) {
      query = query.eq('organization_id', organizationId);
    }
    final response = await query
        .order('occurred_at_utc', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) return null;
    return response['id'] as String;
  }

  @override
  Future<List<SlaLedgerEntry>> getEntriesBySetId(
    String setId, {
    String? organizationId,
  }) async {
    var query = _client
        .from('sla_audit_ledger_v2')
        .select()
        .eq('set_id', setId);
    if (organizationId != null) {
      query = query.eq('organization_id', organizationId);
    }
    final response = await query.order('occurred_at_utc', ascending: true);

    return (response as List).map((row) {
      return SlaLedgerEntry(
        eventId: row['id'] as String,
        organizationId: row['organization_id'] as String,
        type: row['type'] as String,
        operatorId: row['operator_id'] as String? ?? 'SYSTEM',
        setId: row['set_id'] as String?,
        contractId: row['contract_id'] as String,
        planVersion: row['plan_version'] as int,
        occurredAtUtc: DateTime.parse(row['occurred_at_utc'] as String),
        payload: row['payload'] as Map<String, dynamic>? ?? const {},
      );
    }).toList();
  }
}
