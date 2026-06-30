import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

abstract interface class SimulationSeedService {
  Future<int> seedFinancialSnapshots(String organizationId);
}

/// Debug-only: seeds 7 org-level financial snapshot rows so CFO dashboard
/// KPI cards and sparklines show non-zero data after simulation.
class PostgresSimulationSeedService implements SimulationSeedService {
  final SupabaseClient _client;

  const PostgresSimulationSeedService(this._client);

  @override
  Future<int> seedFinancialSnapshots(String organizationId) async {
    final cutoff = DateTime.now().toUtc().subtract(const Duration(days: 7));
    final existing = await _client
        .from('contractual_financial_snapshot')
        .select('id')
        .eq('organization_id', organizationId)
        .isFilter('contract_id', null)
        .gte('operational_date_utc', cutoff.toIso8601String())
        .limit(1);
    if ((existing as List).isNotEmpty) return 0;

    const seed = [
      (daysAgo: 6, protected: 850000, atRisk: 200000, lost: 80000),
      (daysAgo: 5, protected: 880000, atRisk: 185000, lost: 72000),
      (daysAgo: 4, protected: 900000, atRisk: 170000, lost: 65000),
      (daysAgo: 3, protected: 920000, atRisk: 155000, lost: 58000),
      (daysAgo: 2, protected: 940000, atRisk: 140000, lost: 52000),
      (daysAgo: 1, protected: 955000, atRisk: 130000, lost: 47000),
      (daysAgo: 0, protected: 970000, atRisk: 120000, lost: 42000),
    ];

    const uuid = Uuid();
    final now = DateTime.now().toUtc();
    final rows = seed.map((s) {
      final opDate = DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: s.daysAgo));
      final total = s.protected + s.atRisk + s.lost;
      final riskPct = s.atRisk / total * 100;
      final lossPct = s.lost / total * 100;
      return {
        'id': uuid.v4(),
        'organization_id': organizationId,
        'contract_id': null,
        'operational_date_utc': opDate.toIso8601String(),
        'operational_timezone': 'America/Sao_Paulo',
        'closed_at_utc': opDate.add(const Duration(hours: 6)).toIso8601String(),
        'total_contracted_revenue_cents': total,
        'protected_revenue_cents': s.protected,
        'revenue_at_risk_cents': s.atRisk,
        'lost_revenue_cents': s.lost,
        'risk_percentage': riskPct,
        'loss_percentage': lossPct,
        'risk_percentage_bps': (riskPct * 100).round(),
        'loss_percentage_bps': (lossPct * 100).round(),
        'engine_version': 'sim-v1',
        'previous_snapshot_id': null,
      };
    }).toList();

    await _client.from('contractual_financial_snapshot').insert(rows);
    return rows.length;
  }
}

class _NoOpSimulationSeedService implements SimulationSeedService {
  const _NoOpSimulationSeedService();

  @override
  Future<int> seedFinancialSnapshots(String _) async => 0;
}

SimulationSeedService noOpSimulationSeedService() =>
    const _NoOpSimulationSeedService();
