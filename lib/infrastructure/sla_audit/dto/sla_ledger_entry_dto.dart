import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_ledger_entry.dart';

/// DTO that ensures safe mapping between [SlaLedgerEntry] and the Postgres Database.
class SlaLedgerEntryDto {
  final Map<String, dynamic> _data;

  SlaLedgerEntryDto._(this._data);

  /// Validates and maps a domain entry before persisting it.
  /// Enforces limits, strict types, and prevents [double] corruption for cents.
  factory SlaLedgerEntryDto.fromDomain(SlaLedgerEntry entry) {
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

    // Inspect payload for specific business rules (e.g., centavos)
    final payload = Map<String, dynamic>.from(entry.payload);

    // Example: Recursively check if any known financial field is a double instead of int
    _preventDoubleCents(payload);

    return SlaLedgerEntryDto._({
      'organization_id': entry.organizationId,
      'type': entry.type,
      'operator_id': entry.operatorId,
      'set_id': entry.setId,
      'contract_id': entry.contractId,
      'plan_version': entry.planVersion,
      'payload': payload,
      'occurred_at_utc': entry.occurredAtUtc.toIso8601String(),
    });
  }

  static void _preventDoubleCents(Map<String, dynamic> map) {
    final corrections = <String, int>{};
    for (final entry in map.entries) {
      if (entry.key.contains('cents') || entry.key == 'centavos') {
        // dart2js: every JS Number satisfies `is double`, including integers.
        // Only treat as a real double when it is NOT simultaneously an int
        // (i.e., it has a fractional part — genuine financial precision loss).
        if (entry.value is double && entry.value is! int) {
          final d = entry.value as double;
          if (!d.isFinite || d != d.truncateToDouble()) {
            throw IntegrityException(
              'Financial field "${entry.key}" must be an int, found double: ${entry.value}',
              field: entry.key,
            );
          }
          // Whole-number double (web platform representation) — coerce to int.
          corrections[entry.key] = d.toInt();
        }
      }
      if (entry.value is Map<String, dynamic>) {
        _preventDoubleCents(entry.value as Map<String, dynamic>);
      }
    }
    map.addAll(corrections);
  }

  /// Extracts the validated JSON for database persistence.
  Map<String, dynamic> toJson() => _data;

  /// Reconstitutes the domain object safely from raw JSON rows.
  factory SlaLedgerEntryDto.fromJson(Map<String, dynamic> json) {
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
    _preventDoubleCents(payload);

    return SlaLedgerEntryDto._(json);
  }

  SlaLedgerEntry toDomain(String id) {
    final payloadOpt = _data['payload'];
    final payload = payloadOpt != null
        ? Map<String, dynamic>.from(payloadOpt as Map)
        : <String, dynamic>{};

    return SlaLedgerEntry(
      eventId: id,
      organizationId: _data['organization_id'] as String,
      type: _data['type'] as String,
      operatorId: _data['operator_id'] as String? ?? 'SYSTEM',
      setId: _data['set_id'] as String?,
      contractId: _data['contract_id'] as String,
      planVersion: _data['plan_version'] as int,
      occurredAtUtc: DateTime.parse(_data['occurred_at_utc'] as String).toUtc(),
      payload: payload,
    );
  }
}
