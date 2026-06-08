import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [ContractRepository].
///
/// Upserts on [save] to support both creation and state updates
/// (activate, close). Organization isolation is enforced at two layers:
/// 1. Query predicates always include `organization_id`
/// 2. RLS policy on `contracts` table rejects cross-tenant access
class PostgresContractRepository extends BasePostgresRepository
    implements ContractRepository {
  PostgresContractRepository(super.client);

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async {
    try {
      return await executeBatchUpsertInChunks(
        rpcFunction: 'batch_upsert_contracts',
        organizationId: organizationId,
        rows: rows,
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'contract');
    }
  }

  static const _requiredFields = [
    'id',
    'organization_id',
    'name',
    'contractor_name',
    'valid_from_utc',
    'valid_until_utc',
    'status',
    'created_at_utc',
    'penalty_multiplier',
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
  Future<Contract> save(Contract contract) async {
    // Dispatch based on version sentinel:
    // version == 0: new aggregate, never committed to DB → INSERT.
    // version >= 1: loaded via reconstitute() → UPDATE (version bumped by DB trigger).
    if (contract.version == 0) {
      await _create(contract);
      // DB DEFAULT assigns version=1 on INSERT. Reconstitute so the caller's
      // reference reflects the live DB state and subsequent save() calls route
      // to _update(), not _create() again.
      return Contract.reconstitute(
        id: contract.id,
        version: 1,
        organizationId: contract.organizationId,
        name: contract.name,
        contractorName: contract.contractorName,
        contractorId: contract.contractorId,
        description: contract.description,
        validFromUtc: contract.validFromUtc,
        validUntilUtc: contract.validUntilUtc,
        status: contract.status,
        createdAtUtc: contract.createdAtUtc,
        activatedAtUtc: contract.activatedAtUtc,
        closedAtUtc: contract.closedAtUtc,
        closedByUserId: contract.closedByUserId,
        closeReason: contract.closeReason,
        submittedForApprovalAtUtc: contract.submittedForApprovalAtUtc,
        clonedFromContractId: contract.clonedFromContractId,
        financialCeiling: contract.financialCeiling,
        penaltyMultiplierBps: contract.penaltyMultiplierBps,
        latitude: contract.latitude,
        longitude: contract.longitude,
      );
    } else {
      return _update(contract);
    }
  }

  /// Inserts a new contract into the database (first-time persistence).
  Future<void> _create(Contract contract) async {
    try {
      await client.from('contracts').insert({
        'id': contract.id,
        'organization_id': contract.organizationId,
        'name': contract.name,
        'contractor_name': contract.contractorName,
        'contractor_id': contract.contractorId,
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
        'penalty_multiplier':
            contract.penaltyMultiplierBps /
            10000.0, // Physical Metric - Double Required
        'latitude': contract.latitude, // Physical Metric - Double Required
        'longitude': contract.longitude, // Physical Metric - Double Required
        // version starts at 1 in the DB default — no need to send it on insert
      });
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contract',
        resourceId: contract.id,
      );
    }
  }

  /// Updates an existing contract with optimistic locking.
  ///
  /// Uses [updateWithVersion] from [BasePostgresRepository] to ensure that
  /// the update only succeeds if the version in the database matches the
  /// version the client read. Otherwise, throws [ConflictException].
  ///
  /// **Returns** the contract with updated version (reconstituted from DB
  /// response). The caller MUST use this returned instance for any
  /// subsequent operations.
  Future<Contract> _update(Contract contract) async {
    try {
      final newVersion = await updateWithVersion(
        table: 'contracts',
        data: {
          'name': contract.name,
          'contractor_name': contract.contractorName,
          'contractor_id': contract.contractorId,
          'description': contract.description,
          'valid_from_utc': contract.validFromUtc.toIso8601String(),
          'valid_until_utc': contract.validUntilUtc.toIso8601String(),
          'status': contract.status.name,
          'activated_at_utc': contract.activatedAtUtc?.toIso8601String(),
          'closed_at_utc': contract.closedAtUtc?.toIso8601String(),
          'closed_by_user_id': contract.closedByUserId,
          'close_reason': contract.closeReason,
          'cloned_from_contract_id': contract.clonedFromContractId,
          'financial_ceiling_cents': contract.financialCeiling?.cents,
          'submitted_for_approval_at_utc': contract.submittedForApprovalAtUtc
              ?.toIso8601String(),
          'penalty_multiplier':
              contract.penaltyMultiplierBps /
              10000.0, // Physical Metric - Double Required
          'latitude': contract.latitude, // Physical Metric - Double Required
          'longitude': contract.longitude, // Physical Metric - Double Required
        },
        id: contract.id,
        currentVersion: contract.version,
        resourceType: 'contract',
      );
      // Return entity with the new version assigned by the DB trigger.
      // Contract is immutable — reconstitute a new instance with updated version.
      return Contract.reconstitute(
        id: contract.id,
        version: newVersion,
        organizationId: contract.organizationId,
        name: contract.name,
        contractorName: contract.contractorName,
        contractorId: contract.contractorId,
        description: contract.description,
        validFromUtc: contract.validFromUtc,
        validUntilUtc: contract.validUntilUtc,
        status: contract.status,
        createdAtUtc: contract.createdAtUtc,
        activatedAtUtc: contract.activatedAtUtc,
        closedAtUtc: contract.closedAtUtc,
        closedByUserId: contract.closedByUserId,
        closeReason: contract.closeReason,
        submittedForApprovalAtUtc: contract.submittedForApprovalAtUtc,
        clonedFromContractId: contract.clonedFromContractId,
        financialCeiling: contract.financialCeiling,
        penaltyMultiplierBps: contract.penaltyMultiplierBps,
        latitude: contract.latitude,
        longitude: contract.longitude,
      );
    } on ConflictException {
      rethrow; // Already typed — propagate directly (INV-10)
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contract',
        resourceId: contract.id,
      );
    }
  }

  @override
  Future<Contract?> findById(
    String id, {
    required String organizationId,
  }) async {
    try {
      final data = await client
          .from('contracts')
          .select()
          .eq('organization_id', organizationId)
          .eq('id', id)
          .maybeSingle();

      if (data == null) return null;
      assertFields(data);
      return _mapToEntity(data);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contract',
        resourceId: id,
      );
    }
  }

  @override
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  }) async {
    try {
      var query = client
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
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(
        e,
        resourceType: 'contract',
        resourceId: organizationId,
      );
    }
  }

  // ── Private mapper ─────────────────────────────────────────

  Contract _mapToEntity(Map<String, dynamic> row) {
    return Contract.reconstitute(
      id: row['id'] as String,
      version: (row['version'] as num?)?.toInt() ?? 1,
      organizationId: row['organization_id'] as String,
      name: row['name'] as String,
      contractorName: row['contractor_name'] as String,
      contractorId: row['contractor_id'] as String?,
      description: row['description'] as String?,
      validFromUtc: parseUtc(row['valid_from_utc'], 'valid_from_utc'),
      validUntilUtc: parseUtc(row['valid_until_utc'], 'valid_until_utc'),
      status: IntegrityException.shield(
        ContractStatus.values,
        row['status'] as String,
        'status',
      ),
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
      penaltyMultiplierBps: ((row['penalty_multiplier'] as num) * 10000)
          .round(),
      latitude: row['latitude'] != null
          ? (row['latitude'] as num).toDouble()
          : null, // Physical Metric - Double Required
      longitude: row['longitude'] != null
          ? (row['longitude'] as num).toDouble()
          : null, // Physical Metric - Double Required
      previousHash: row['previous_hash'] as String?,
      currentHash: row['current_hash'] as String?,
    );
  }
}
