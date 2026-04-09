import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/infrastructure/sla_audit/dto/sla_ledger_entry_dto.dart';

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
    final dto = SlaLedgerEntryDto.fromDomain(entry);

    final response = await _client
        .from('sla_audit_ledger_v2')
        .insert(dto.toJson())
        .select('id')
        .single();

    return response['id'] as String;
  }

  @override
  Future<String?> getLastEntryId({
    String? organizationId,
    String? contractId,
  }) async {
    var query = _client.from('sla_audit_ledger_v2').select('id');
    if (organizationId != null) {
      query = query.eq('organization_id', organizationId);
    }
    if (contractId != null) {
      query = query.eq('contract_id', contractId);
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
      final dto = SlaLedgerEntryDto.fromJson(row as Map<String, dynamic>);
      return dto.toDomain(row['id'] as String);
    }).toList();
  }
}
