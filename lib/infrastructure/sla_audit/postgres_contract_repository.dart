import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';

/// Postgres implementation of [ContractRepository].
///
/// Upserts on [save] to support both creation and state updates
/// (activate, close). Organization isolation is enforced at two layers:
/// 1. Query predicates always include `organization_id`
/// 2. RLS policy on `contracts` table rejects cross-tenant access
class PostgresContractRepository implements ContractRepository {
  final SupabaseClient? _injectedClient;

  // Lazy accessor — unit tests that only call assertFields/parseUtc
  // do not trigger Supabase.instance before initialization.
  SupabaseClient get _client => _injectedClient ?? supabase;

  PostgresContractRepository([SupabaseClient? client])
    : _injectedClient = client;

  static const _requiredFields = [
    'id',
    'organization_id',
    'name',
    'contractor_name',
    'valid_from_utc',
    'valid_until_utc',
    'status',
    'created_at_utc',
  ];

  /// Validates that all required columns are present in a DB row before mapping.
  /// Throws [IntegrityException] on any absent or null field. (INV-18)
  @visibleForTesting
  void assertFields(Map<String, dynamic> row) {
    for (final field in _requiredFields) {
      if (!row.containsKey(field) || row[field] == null) {
        throw IntegrityException(
          'Required field "$field" absent or null in contracts',
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
  Future<void> save(Contract contract) async {
    await _client.from('contracts').upsert({
      'id': contract.id,
      'organization_id': contract.organizationId,
      'name': contract.name,
      'contractor_name': contract.contractorName,
      'description': contract.description,
      'valid_from_utc': contract.validFromUtc.toIso8601String(),
      'valid_until_utc': contract.validUntilUtc.toIso8601String(),
      'status': contract.status.name,
      'created_at_utc': contract.createdAtUtc.toIso8601String(),
      'activated_at_utc': contract.activatedAtUtc?.toIso8601String(),
      'closed_at_utc': contract.closedAtUtc?.toIso8601String(),
      'closed_by_user_id': contract.closedByUserId,
      'close_reason': contract.closeReason,
      'cloned_from_contract_id': contract.clonedFromContractId,
      'financial_ceiling_cents': contract.financialCeiling?.cents,
      'submitted_for_approval_at_utc': contract.submittedForApprovalAtUtc
          ?.toIso8601String(),
    });
  }

  @override
  Future<Contract?> findById(
    String id, {
    required String organizationId,
  }) async {
    final data = await _client
        .from('contracts')
        .select()
        .eq('organization_id', organizationId)
        .eq('id', id)
        .maybeSingle();

    if (data == null) return null;
    assertFields(data);
    return _mapToEntity(data);
  }

  @override
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  }) async {
    var query = _client
        .from('contracts')
        .select()
        .eq('organization_id', organizationId);

    if (status != null) {
      query = query.eq('status', status.name);
    }

    final List<dynamic> rows = await query.order(
      'created_at_utc',
      ascending: false,
    );

    return rows.map((r) {
      final row = r as Map<String, dynamic>;
      assertFields(row);
      return _mapToEntity(row);
    }).toList();
  }

  // ── Private mapper ─────────────────────────────────────────

  Contract _mapToEntity(Map<String, dynamic> row) {
    return Contract.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      name: row['name'] as String,
      contractorName: row['contractor_name'] as String,
      description: row['description'] as String?,
      validFromUtc: parseUtc(row['valid_from_utc'], 'valid_from_utc'),
      validUntilUtc: parseUtc(row['valid_until_utc'], 'valid_until_utc'),
      status: ContractStatus.values.byName(row['status'] as String),
      createdAtUtc: parseUtc(row['created_at_utc'], 'created_at_utc'),
      activatedAtUtc: row['activated_at_utc'] != null
          ? parseUtc(row['activated_at_utc'], 'activated_at_utc')
          : null,
      closedAtUtc: row['closed_at_utc'] != null
          ? parseUtc(row['closed_at_utc'], 'closed_at_utc')
          : null,
      closedByUserId: row['closed_by_user_id'] as String?,
      closeReason: row['close_reason'] as String?,
      submittedForApprovalAtUtc: row['submitted_for_approval_at_utc'] != null
          ? parseUtc(
              row['submitted_for_approval_at_utc'],
              'submitted_for_approval_at_utc',
            )
          : null,
      clonedFromContractId: row['cloned_from_contract_id'] as String?,
      financialCeiling: row['financial_ceiling_cents'] != null
          ? Money((row['financial_ceiling_cents'] as num).toInt())
          : null,
    );
  }
}
