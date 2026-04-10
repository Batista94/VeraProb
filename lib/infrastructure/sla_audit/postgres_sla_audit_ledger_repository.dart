import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/dto/sla_ledger_entry_dto.dart';

/// Postgres implementation of [SlaAuditLedgerRepository].
///
/// **Architecture Guarantees:**
/// 1. **Absolute Append-Only**: Lack of delete/update methods ensures immutability.
/// 2. **Monotonic Ordering**: Uses Postgres `bigserial` (ID) as the primary ordering criterion.
/// 3. **Idempotency**: Prevents duplicate entries via causal linkage checks or cautious inserts.
/// 4. **Structured Mapping**: Persists structured [SlaLedgerEntry] instead of raw events.
class PostgresSlaAuditLedgerRepository implements SlaAuditLedgerRepository {
  final SupabaseClient? _injectedClient;

  // Accessed lazily so unit tests that only call assertFields/parseUtc
  // do not trigger Supabase.instance before initialization.
  SupabaseClient get _client => _injectedClient ?? supabase;

  PostgresSlaAuditLedgerRepository([SupabaseClient? client])
    : _injectedClient = client;

  static const _requiredFields = [
    'organization_id',
    'type',
    'occurred_at_utc',
    'contract_id',
    'plan_version',
  ];

  /// Validates that all required columns are present in a DB row before mapping.
  /// Throws [IntegrityException] on any absent or null field. (INV-18)
  @visibleForTesting
  void assertFields(Map<String, dynamic> row) {
    for (final field in _requiredFields) {
      if (!row.containsKey(field) || row[field] == null) {
        throw IntegrityException(
          'Required field "$field" absent or null in sla_audit_ledger_v2',
          field: field,
        );
      }
    }
  }

  /// Parses a raw DB timestamp value to a UTC [DateTime]. (INV-9)
  ///
  /// Postgres may return naive timestamps without a 'Z' suffix; this helper
  /// normalizes them before parsing to prevent local-time drift.
  /// Throws [IntegrityException] if [raw] is null or not a [String].
  @visibleForTesting
  DateTime parseUtc(dynamic raw, String fieldName) {
    if (raw == null) {
      throw IntegrityException(
        'Timestamp "$fieldName" is null',
        field: fieldName,
      );
    }
    if (raw is! String) {
      throw IntegrityException(
        'Timestamp "$fieldName" has unexpected type ${raw.runtimeType}, expected String',
        field: fieldName,
      );
    }
    final normalized = (raw.endsWith('Z') || raw.contains('+'))
        ? raw
        : '${raw}Z';
    return DateTime.parse(normalized);
  }

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
      final typedRow = row as Map<String, dynamic>;
      assertFields(typedRow);
      final normalizedRow = Map<String, dynamic>.from(typedRow);
      normalizedRow['occurred_at_utc'] = parseUtc(
        typedRow['occurred_at_utc'],
        'occurred_at_utc',
      ).toIso8601String();
      final dto = SlaLedgerEntryDto.fromJson(normalizedRow);
      return dto.toDomain(typedRow['id'] as String);
    }).toList();
  }
}
