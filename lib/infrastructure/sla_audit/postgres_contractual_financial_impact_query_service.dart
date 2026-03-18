import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/shared/money.dart';
import '../../application/sla_audit/projections/contractual_financial_impact.dart';
import '../../application/sla_audit/projections/contractual_financial_impact_query_service.dart';

/// Postgres implementation for [ContractualFinancialImpactQueryService].
/// Extracts financial impact projection directly from `contractual_financial_snapshot`.
class ContractualFinancialImpactQueryServicePostgres
    implements ContractualFinancialImpactQueryService {
  final SupabaseClient _client;

  ContractualFinancialImpactQueryServicePostgres(this._client);

  @override
  Future<ContractualFinancialImpact> getImpact({
    required String organizationId,
    String? contractId,
  }) async {
    var query = _client.from('contractual_financial_snapshot').select();

    query = query.eq('organization_id', organizationId);

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    } else {
      query = query.isFilter('contract_id', null);
    }

    // Fetch the latest snapshots. Limit to 31 to avoid loading the full snapshot history.
    // Assuming the most recent active snapshot is within the last month of reprocessing.
    final rows = await query
        .order('operational_date_utc', ascending: false)
        .limit(31);

    if (rows.isEmpty) {
      return ContractualFinancialImpact(
        contractId: contractId,
        generatedAtUtc: DateTime.now().toUtc(),
        totalContractedRevenue: const Money(0),
        protectedRevenue: const Money(0),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        riskPercentage: 0.0,
        lossPercentage: 0.0,
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
    final marginErosionPercent = (ceilingCents != null && ceilingCents > 0)
        ? lostRevenueCents / ceilingCents * 100.0
        : null;

    return ContractualFinancialImpact(
      contractId: contractId,
      generatedAtUtc: DateTime.parse(latest['closed_at_utc'] as String).toUtc(),
      totalContractedRevenue: Money(
        (latest['total_contracted_revenue_cents'] as num).toInt(),
      ),
      protectedRevenue: Money(
        (latest['protected_revenue_cents'] as num).toInt(),
      ),
      revenueAtRisk: Money((latest['revenue_at_risk_cents'] as num).toInt()),
      lostRevenue: Money(lostRevenueCents),
      riskPercentage: (latest['risk_percentage'] as num).toDouble(),
      lossPercentage: (latest['loss_percentage'] as num).toDouble(),
      marginErosionPercent: marginErosionPercent,
    );
  }
}
