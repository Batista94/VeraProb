import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact_query_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

/// Postgres implementation for [ContractualFinancialImpactQueryService].
///
/// Reads live financial aggregates from the `get_financial_impact_summary` RPC
/// (sanction_review_queue truth source) instead of the stale snapshot table.
/// INV-2: org isolation enforced server-side via JWT `app_metadata.org_id`.
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
    final raw = await _client.rpc(
      'get_financial_impact_summary',
      params: {'p_org_id': organizationId},
    );

    if (raw == null) {
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

    final map = raw as Map<String, dynamic>;
    final protected = (map['protected_revenue_cents'] as num?)?.toInt() ?? 0;
    final atRisk = (map['revenue_at_risk_cents'] as num?)?.toInt() ?? 0;
    final lost = (map['lost_revenue_cents'] as num?)?.toInt() ?? 0;
    final total = protected + atRisk + lost;

    // BPS = basis points relative to total (avoid division by zero)
    final riskBps = total > 0 ? (atRisk * 10000 ~/ total) : 0;
    final lossBps = total > 0 ? (lost * 10000 ~/ total) : 0;

    return ContractualFinancialImpact(
      contractId: contractId,
      generatedAtUtc: _dateTimeProvider.nowUtc(),
      totalContractedRevenue: total,
      protectedRevenue: protected,
      revenueAtRisk: atRisk,
      lostRevenue: lost,
      riskPercentageBps: riskBps,
      lossPercentageBps: lossBps,
    );
  }
}
