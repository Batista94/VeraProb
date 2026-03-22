import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/shared/money.dart';
import '../../domain/sla_audit/contractual_financial_daily_snapshot.dart';
import '../../domain/sla_audit/contractual_financial_snapshot_repository.dart';

/// PostgreSQL implementation of [ContractualFinancialSnapshotRepository].
///
/// Strictly adheres to immutability invariants: only provides `save` (INSERT),
/// lacking any `UPDATE` or `DELETE` capabilities.
///
/// Active snapshots are inferred dynamically by evaluating the reprocessing
/// chain in memory after fetching records, guaranteeing that only the most
/// recent snapshot of a chain represents the official closed status.
class PostgresContractualFinancialSnapshotRepository
    implements ContractualFinancialSnapshotRepository {
  final SupabaseClient _client;

  PostgresContractualFinancialSnapshotRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  @override
  Future<void> save(ContractualFinancialDailySnapshot snapshot) async {
    await _client.from('contractual_financial_snapshot').insert({
      'id': snapshot.id,
      'organization_id': snapshot.organizationId,
      'contract_id': snapshot.contractId,
      'operational_date_utc': snapshot.operationalDateUtc.toIso8601String(),
      'operational_timezone': snapshot.operationalTimezone,
      'closed_at_utc': snapshot.closedAtUtc.toIso8601String(),
      'total_contracted_revenue_cents': snapshot.totalContractedRevenue.cents,
      'protected_revenue_cents': snapshot.protectedRevenue.cents,
      'revenue_at_risk_cents': snapshot.revenueAtRisk.cents,
      'lost_revenue_cents': snapshot.lostRevenue.cents,
      'risk_percentage': snapshot.riskPercentage,
      'loss_percentage': snapshot.lossPercentage,
      'total_obligations': snapshot.totalObligations,
      'executed_count': snapshot.executedCount,
      'no_show_count': snapshot.noShowCount,
      'evidence_gap_count': snapshot.evidenceGapCount,
      'last_ledger_entry_id': snapshot.lastLedgerEntryId,
      'previous_snapshot_id': snapshot.previousSnapshotId,
      'reprocessing_reason': snapshot.reprocessingReason,
      'author_user_id': snapshot.authorUserId,
    });
  }

  @override
  Future<List<ContractualFinancialDailySnapshot>> findAll({
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client
        .from('contractual_financial_snapshot')
        .select()
        .eq('organization_id', organizationId);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    final response = await query;
    final snapshots = (response as List).map((row) => _mapRow(row)).toList();

    // Infer active snapshots by chaining (those that are not superseded)
    final supersededIds = snapshots
        .where((s) => s.previousSnapshotId != null)
        .map((s) => s.previousSnapshotId!)
        .toSet();

    return snapshots.where((s) => !supersededIds.contains(s.id)).toList();
  }

  @override
  Future<List<ContractualFinancialDailySnapshot>> findByDateRange({
    required String organizationId,
    required DateTime startUtc,
    required DateTime endUtc,
    String? contractId,
  }) async {
    var query = _client
        .from('contractual_financial_snapshot')
        .select()
        .eq('organization_id', organizationId)
        .gte('operational_date_utc', startUtc.toIso8601String())
        .lte('operational_date_utc', endUtc.toIso8601String());

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    }

    final response = await query;
    final snapshots = (response as List).map((row) => _mapRow(row)).toList();

    // Redundant but safe: ensure we only return active snapshots even in date ranges
    final supersededIds = snapshots
        .where((s) => s.previousSnapshotId != null)
        .map((s) => s.previousSnapshotId!)
        .toSet();

    return snapshots.where((s) => !supersededIds.contains(s.id)).toList();
  }

  @override
  Future<bool> existsForDate(
    String organizationId,
    DateTime operationalDateUtc, {
    String? contractId,
  }) async {
    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );

    // An automated snapshot should not be generated if an ACTIVE snapshot exists for this date.
    final allActive = await findAll(
      organizationId: organizationId,
      contractId: contractId,
    );
    return allActive.any((s) => s.operationalDateUtc == normalizedDate);
  }

  ContractualFinancialDailySnapshot _mapRow(Map<String, dynamic> row) {
    return ContractualFinancialDailySnapshot.reconstitute(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      contractId: row['contract_id'] as String?,
      operationalDateUtc: DateTime.parse(row['operational_date_utc'] as String).toUtc(),
      operationalTimezone: row['operational_timezone'] as String,
      closedAtUtc: DateTime.parse(row['closed_at_utc'] as String).toUtc(),
      totalContractedRevenue: Money(
        row['total_contracted_revenue_cents'] as int,
      ),
      protectedRevenue: Money(row['protected_revenue_cents'] as int),
      revenueAtRisk: Money(row['revenue_at_risk_cents'] as int),
      lostRevenue: Money(row['lost_revenue_cents'] as int),
      riskPercentage: (row['risk_percentage'] as num).toDouble(),
      lossPercentage: (row['loss_percentage'] as num).toDouble(),
      totalObligations: (row['total_obligations'] as num?)?.toInt() ?? 0,
      executedCount: (row['executed_count'] as num?)?.toInt() ?? 0,
      noShowCount: (row['no_show_count'] as num?)?.toInt() ?? 0,
      evidenceGapCount: (row['evidence_gap_count'] as num?)?.toInt() ?? 0,
      lastLedgerEntryId: row['last_ledger_entry_id'] as String?,
      previousSnapshotId: row['previous_snapshot_id'] as String?,
      reprocessingReason: row['reprocessing_reason'] as String?,
      authorUserId: row['author_user_id'] as String?,
    );
  }
}
