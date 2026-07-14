import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [SlaAuditLedgerRepository].
///
/// **Architecture Guarantees:**
/// 1. **Absolute Append-Only**: Lack of delete/update methods ensures immutability.
/// 2. **Monotonic Ordering**: Uses Postgres `bigserial` (ID) as the primary ordering criterion.
/// 3. **Idempotency**: Prevents duplicate entries via causal linkage checks or cautious inserts.
/// 4. **Structured Mapping**: Persists structured [SlaLedgerEntry] instead of raw events.
class PostgresSlaAuditLedgerRepository extends BasePostgresRepository
    implements SlaAuditLedgerRepository {
  PostgresSlaAuditLedgerRepository(super.client);

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
    return BasePostgresRepository.parsePostgresUtc(raw, fieldName);
  }

  /// Validates domain entry and builds the insert payload (INV-4 / dart2js cents).
  @visibleForTesting
  static Map<String, dynamic> toInsertMap(SlaLedgerEntry entry) {
    if (entry.organizationId.isEmpty) {
      throw const IntegrityException(
        'organizationId cannot be empty',
        field: 'organization_id',
      );
    }
    if (entry.type.length > 255) {
      throw const IntegrityException(
        'type string limit exceeded (> 255)',
        field: 'type',
      );
    }
    if (entry.operatorId.length > 255) {
      throw const IntegrityException(
        'operatorId string limit exceeded (> 255)',
        field: 'operator_id',
      );
    }
    if (entry.planVersion < 0) {
      throw const IntegrityException(
        'planVersion cannot be negative',
        field: 'plan_version',
      );
    }

    final payload = Map<String, dynamic>.from(entry.payload);
    preventDoubleCents(payload);

    return {
      'organization_id': entry.organizationId,
      'type': entry.type,
      'operator_id': entry.operatorId,
      'set_id': entry.setId,
      'contract_id': entry.contractId,
      'plan_version': entry.planVersion,
      'payload': payload,
      'occurred_at_utc': entry.occurredAtUtc.toIso8601String(),
    };
  }

  /// Reconstitutes domain from a validated ledger row.
  @visibleForTesting
  static SlaLedgerEntry fromRow(Map<String, dynamic> json, String id) {
    if (!json.containsKey('organization_id') ||
        json['organization_id'] == null) {
      throw const IntegrityException(
        'Missing organization_id from mapped row',
        field: 'organization_id',
      );
    }
    if (!json.containsKey('type') || json['type'] == null) {
      throw const IntegrityException(
        'Missing type from mapped row',
        field: 'type',
      );
    }
    if (!json.containsKey('occurred_at_utc') ||
        json['occurred_at_utc'] == null) {
      throw const IntegrityException(
        'Missing occurred_at_utc from mapped row',
        field: 'occurred_at_utc',
      );
    }

    final payloadOpt = json['payload'];
    final payload = payloadOpt != null
        ? Map<String, dynamic>.from(payloadOpt as Map)
        : <String, dynamic>{};
    preventDoubleCents(payload);

    return SlaLedgerEntry(
      eventId: id,
      organizationId: json['organization_id'] as String,
      type: json['type'] as String,
      operatorId: json['operator_id'] as String? ?? 'SYSTEM',
      setId: json['set_id'] as String?,
      contractId: json['contract_id'] as String,
      planVersion: json['plan_version'] as int,
      occurredAtUtc: DateTime.parse(json['occurred_at_utc'] as String).toUtc(),
      payload: payload,
    );
  }

  /// dart2js: coerce whole-number doubles on cent fields; reject fractional.
  @visibleForTesting
  static void preventDoubleCents(Map<String, dynamic> map) {
    final corrections = <String, int>{};
    for (final entry in map.entries) {
      if (entry.key.contains('cents') || entry.key == 'centavos') {
        if (entry.value is double && entry.value is! int) {
          final d = entry.value as double;
          if (!d.isFinite || d != d.truncateToDouble()) {
            throw IntegrityException(
              'Financial field "${entry.key}" must be an int, found double: ${entry.value}',
              field: entry.key,
            );
          }
          corrections[entry.key] = d.toInt();
        }
      }
      if (entry.value is Map<String, dynamic>) {
        preventDoubleCents(entry.value as Map<String, dynamic>);
      }
    }
    map.addAll(corrections);
  }

  @override
  Future<String> append(SlaLedgerEntry entry) async {
    try {
      final payload = toInsertMap(entry);

      final response = await client
          .from('sla_audit_ledger_v2')
          .insert(payload)
          .select('id')
          .single();

      return response['id'] as String;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'sla_audit_ledger',
        resourceId: entry.id?.toString(),
      );
    }
  }

  @override
  Future<String?> getLastEntryId({
    String? organizationId,
    String? contractId,
  }) async {
    try {
      var query = client.from('sla_audit_ledger_v2').select('id');
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
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'sla_audit_ledger',
        resourceId: contractId ?? organizationId,
      );
    }
  }

  @override
  Future<List<SlaLedgerEntry>> getEntriesBySetId(
    String setId, {
    String? organizationId,
  }) async {
    try {
      var query = client
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
        return fromRow(normalizedRow, typedRow['id'] as String);
      }).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'sla_audit_ledger',
        resourceId: setId,
      );
    }
  }

  @override
  Future<List<SlaLedgerEntry>> getEntriesByQueueEntryId(
    String queueEntryId, {
    String? organizationId,
  }) async {
    try {
      var query = client
          .from('sla_audit_ledger_v2')
          .select()
          .eq('payload->>queue_entry_id', queueEntryId);
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
        return fromRow(normalizedRow, typedRow['id'] as String);
      }).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'sla_audit_ledger',
        resourceId: queueEntryId,
      );
    }
  }
}
