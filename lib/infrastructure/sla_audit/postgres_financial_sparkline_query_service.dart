import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/application/sla_audit/projections/financial_sparkline_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_series.dart';

class PostgresFinancialSparklineQueryService
    implements FinancialSparklineQueryService {
  final SupabaseClient _client;

  const PostgresFinancialSparklineQueryService(this._client);

  @override
  Future<FinancialSparklineSeries> getSparkline({
    required String organizationId,
    required int days,
  }) async {
    final raw =
        await _client.rpc(
              'get_financial_trend_sparkline',
              params: {'p_org_id': organizationId, 'p_days': days},
            )
            as List<dynamic>;

    if (raw.isEmpty) return FinancialSparklineSeries.empty;

    final protectedCents = <int>[];
    final atRiskCents = <int>[];
    final lostCents = <int>[];
    final datesUtc = <DateTime>[];

    for (final e in raw) {
      final point = e as Map<String, dynamic>;
      protectedCents.add((point['protected_cents'] as num).toInt());
      atRiskCents.add((point['at_risk_cents'] as num).toInt());
      lostCents.add((point['lost_cents'] as num).toInt());
      datesUtc.add(DateTime.parse(point['d'] as String).toUtc());
    }

    return FinancialSparklineSeries(
      protectedCents: protectedCents,
      atRiskCents: atRiskCents,
      lostCents: lostCents,
      datesUtc: datesUtc,
    );
  }
}
