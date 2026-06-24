import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/analytics/carrier_ranking_query_service.dart';
import 'package:veraprob/application/analytics/fleet_risk_query_service.dart';
import 'package:veraprob/application/analytics/carrier_performance_rank.dart';
import 'package:veraprob/application/analytics/fleet_risk_window.dart';
import 'package:veraprob/infrastructure/analytics/supabase_carrier_ranking_query_service.dart';
import 'package:veraprob/infrastructure/analytics/supabase_fleet_risk_query_service.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/state/provider_timeout.dart';
import 'auth_providers.dart';

// ── Query service providers (INV-13: features depend on these, not infra) ────

final carrierRankingQueryServiceProvider = Provider<CarrierRankingQueryService>(
  (ref) =>
      SupabaseCarrierRankingQueryService(ref.watch(supabaseClientProvider)),
);

final fleetRiskQueryServiceProvider = Provider<FleetRiskQueryService>(
  (ref) => SupabaseFleetRiskQueryService(ref.watch(supabaseClientProvider)),
);

/// Caches an autoDispose provider's result for [ttl] after the last listener
/// detaches, then releases it (INV-16: bound redundant RPCs without pinning
/// the result forever).
void _cacheFor(Ref ref, Duration ttl) {
  final link = ref.keepAlive();
  final timer = Timer(ttl, link.close);
  ref.onDispose(timer.cancel);
}

// ── Carrier Performance Ranking ──────────────────────────────────────────────

/// Worst-first carrier compliance ranking for the current org. Returns an empty
/// list when unauthenticated. Cached 60s.
final carrierRankingProvider =
    FutureProvider.autoDispose<List<CarrierPerformanceRank>>((ref) async {
      final organizationId = ref.watch(currentOrganizationIdProvider);
      if (organizationId == null) return const [];
      _cacheFor(ref, const Duration(seconds: 60));

      return ref
          .watch(carrierRankingQueryServiceProvider)
          .getRanking(organizationId: organizationId)
          .withProviderTimeout();
    });

// ── Fleet Risk Summary ───────────────────────────────────────────────────────

/// Active SLA windows ranked worst-first with server-computed risk. Replaces
/// the in-app per-row breach calculation on the fleet panel. Cached 30s.
final fleetRiskSummaryProvider =
    FutureProvider.autoDispose<List<FleetRiskWindow>>((ref) async {
      final organizationId = ref.watch(currentOrganizationIdProvider);
      if (organizationId == null) return const [];
      _cacheFor(ref, const Duration(seconds: 30));

      return ref
          .watch(fleetRiskQueryServiceProvider)
          .listFleetRisk(organizationId: organizationId)
          .withProviderTimeout();
    });

/// Highest risk among active windows — the thermometer sentinel. Null when no
/// active windows (nothing to show).
final fleetRiskSentinelProvider = Provider.autoDispose<FleetRiskWindow?>((ref) {
  final windows = ref.watch(fleetRiskSummaryProvider).asData?.value;
  if (windows == null || windows.isEmpty) return null;
  // RPC already orders worst-first, but fold defensively.
  return windows.reduce(
    (FleetRiskWindow a, FleetRiskWindow b) => a.riskBps >= b.riskBps ? a : b,
  );
});
