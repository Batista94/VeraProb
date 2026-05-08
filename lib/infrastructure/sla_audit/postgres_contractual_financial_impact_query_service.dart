import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact_query_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// Postgres implementation for [ContractualFinancialImpactQueryService].
/// Extracts financial impact projection directly from `contractual_financial_snapshot`.
class ContractualFinancialImpactQueryServicePostgres
    implements ContractualFinancialImpactQueryService {
  final SupabaseClient _client;
  final IDateTimeProvider _dateTimeProvider;

  ContractualFinancialImpactQueryServicePostgres(
    this._client,
    this._dateTimeProvider,
  );

  @override
  Future<ContractualFinancialImpact> getImpact({
    required String organizationId,
    String? contractId,
    DateTime? startUtc,
    DateTime? endUtc,
  }) async {
    var query = _client.from('contractual_financial_snapshot').select();

    query = query.eq('organization_id', organizationId);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    } else {
      query = query.isFilter('contract_id', null);
    }

    // Application layer provides the temporal window â€” infrastructure only maps it to Postgres.
    if (startUtc != null) {
      query = query.gte(
        'operational_date_utc',
        startUtc.toUtc().toIso8601String(),
      );
    }
    if (endUtc != null) {
      query = query.lte(
        'operational_date_utc',
        endUtc.toUtc().toIso8601String(),
      );
    }

    // Fetch the latest snapshots. Limit to 31 to avoid loading the full snapshot history.
    // Assuming the most recent active snapshot is within the last month of reprocessing.
    final rows = await query
        .order('operational_date_utc', ascending: false)
        .limit(31);

    if (rows.isEmpty) {
      return ContractualFinancialImpact(
        contractId: contractId,
        generatedAtUtc: _dateTimeProvider.nowUtc(),
        totalContractedRevenue: 0,
        protectedRevenue: 0,
        revenueAtRisk: 0,
        lostRevenue: 0,
        riskPercentageBps: 0,
        lossPercentageBps: 0,
      );
    }

    // Load financial ceiling for marginErosionPercent (contract-scoped only).
    int? ceilingCents;
    if (contractId != null) {
      final contractRow = await _client
          .from('contracts')
          .select('financial_ceiling_cents')
          .eq('organization_id', organizationId)
          .eq('id', contractId)
          .maybeSingle();
      ceilingCents = contractRow?['financial_ceiling_cents'] as int?;
    }

    // Identify superseded snapshots (those referenced by another snapshot's previous_snapshot_id)
    final supersededIds = rows
        .where((row) => row['previous_snapshot_id'] != null)
        .map((row) => row['previous_snapshot_id'] as String)
        .toSet();

    // Filter to active and get the latest
    final activeRows = rows
        .where((row) => !supersededIds.contains(row['id']))
        .toList();

    // Rows are already ordered descending, so the very first active row is the latest
    final latest = activeRows.first;

    final lostRevenueCents = (latest['lost_revenue_cents'] as num).toInt();
    final marginErosionBps = (ceilingCents != null && ceilingCents > 0)
        ? (lostRevenueCents * 10000 ~/ ceilingCents)
        : null;

    return ContractualFinancialImpact(
      contractId: contractId,
      generatedAtUtc: DateTime.parse(latest['closed_at_utc'] as String).toUtc(),
      totalContractedRevenue: (latest['total_contracted_revenue_cents'] as num)
          .toInt(),
      protectedRevenue: (latest['protected_revenue_cents'] as num).toInt(),
      revenueAtRisk: (latest['revenue_at_risk_cents'] as num).toInt(),
      lostRevenue: lostRevenueCents,
      riskPercentageBps: (latest['risk_percentage'] as num).toInt(),
      lossPercentageBps: (latest['loss_percentage'] as num).toInt(),
      marginErosionBps: marginErosionBps,
    );
  }
}
