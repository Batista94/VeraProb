import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/shared/money.dart';
import '../../application/sla_audit/projections/contractual_financial_trend_point.dart';
import '../../application/sla_audit/projections/contractual_financial_trend_query_service.dart';

/// Postgres implementation for [ContractualFinancialTrendQueryService].
/// Extracts time-series financial trend projection directly from `contractual_financial_snapshot`.
class ContractualFinancialTrendQueryServicePostgres
    implements ContractualFinancialTrendQueryService {
  final SupabaseClient _client;

  ContractualFinancialTrendQueryServicePostgres(this._client);

  @override
  Future<List<ContractualFinancialTrendPoint>> getTrend({
    String? contractId,
  }) async {
    var query = _client.from('contractual_financial_snapshot').select();

    if (contractId != null) {
      query = query.eq('contract_id', contractId);
    } else {
      query = query.isFilter('contract_id', null);
    }

    // Fetch the snapshots limit loosely to the last year to avoid fetching the full table.
    final rows = await query
        .order('operational_date_utc', ascending: false)
        .limit(365);

    if (rows.isEmpty) return [];

    // Identify superseded snapshots
    final supersededIds = rows
        .where((row) => row['previous_snapshot_id'] != null)
        .map((row) => row['previous_snapshot_id'] as String)
        .toSet();

    // Filter to active
    final activeRows = rows
        .where((row) => !supersededIds.contains(row['id']))
        .toList();

    // The read model expects chronological order (ascending)
    activeRows.sort(
      (a, b) => (a['operational_date_utc'] as String).compareTo(
        b['operational_date_utc'] as String,
      ),
    );

    return activeRows.map((snapshot) {
      final dateUtc = DateTime.parse(
        snapshot['operational_date_utc'] as String,
      ).toUtc();
      final formattedDate = DateFormat('dd/MM/yyyy', 'pt_BR').format(dateUtc);

      final contracted = Money(
        (snapshot['total_contracted_revenue_cents'] as num).toInt(),
      );

      return ContractualFinancialTrendPoint(
        dateUtc: dateUtc,
        formattedDate: formattedDate,
        baseRevenueUsedForCalculation: contracted,
        totalContractedRevenue: contracted,
        protectedRevenue: Money(
          (snapshot['protected_revenue_cents'] as num).toInt(),
        ),
        revenueAtRisk: Money(
          (snapshot['revenue_at_risk_cents'] as num).toInt(),
        ),
        lostRevenue: Money((snapshot['lost_revenue_cents'] as num).toInt()),
        riskPercentage: (snapshot['risk_percentage'] as num).toDouble(),
        lossPercentage: (snapshot['loss_percentage'] as num).toDouble(),
      );
    }).toList();
  }
}
