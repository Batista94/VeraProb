import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/core/config/supabase_client.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/shared/money.dart';

/// Postgres implementation of [ContractRepository].
///
/// Upserts on [save] to support both creation and state updates
/// (activate, close). Organization isolation is enforced at two layers:
/// 1. Query predicates always include `organization_id`
/// 2. RLS policy on `contracts` table rejects cross-tenant access
class PostgresContractRepository implements ContractRepository {
  final SupabaseClient _client;

  PostgresContractRepository([SupabaseClient? client])
    : _client = client ?? supabase;

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

    return rows.map((r) => _mapToEntity(r)).toList();
  }

  // ── Private mapper ─────────────────────────────────────────

  Contract _mapToEntity(Map<String, dynamic> row) {
    return Contract.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      name: row['name'] as String,
      contractorName: row['contractor_name'] as String,
      description: row['description'] as String?,
      validFromUtc: DateTime.parse(row['valid_from_utc'] as String).toUtc(),
      validUntilUtc: DateTime.parse(row['valid_until_utc'] as String).toUtc(),
      status: ContractStatus.values.byName(row['status'] as String),
      createdAtUtc: DateTime.parse(row['created_at_utc'] as String).toUtc(),
      activatedAtUtc: row['activated_at_utc'] != null
          ? DateTime.parse(row['activated_at_utc'] as String).toUtc()
          : null,
      closedAtUtc: row['closed_at_utc'] != null
          ? DateTime.parse(row['closed_at_utc'] as String).toUtc()
          : null,
      closedByUserId: row['closed_by_user_id'] as String?,
      closeReason: row['close_reason'] as String?,
      submittedForApprovalAtUtc: row['submitted_for_approval_at_utc'] != null
          ? DateTime.parse(
              row['submitted_for_approval_at_utc'] as String,
            ).toUtc()
          : null,
      clonedFromContractId: row['cloned_from_contract_id'] as String?,
      financialCeiling: row['financial_ceiling_cents'] != null
          ? Money((row['financial_ceiling_cents'] as num).toInt())
          : null,
    );
  }
}
