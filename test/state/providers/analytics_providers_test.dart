import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/analytics/carrier_performance_rank.dart';
import 'package:veraprob/application/analytics/carrier_ranking_query_service.dart';
import 'package:veraprob/application/analytics/fleet_risk_query_service.dart';
import 'package:veraprob/application/analytics/fleet_risk_window.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/state/providers/analytics_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

class _FakeRanking implements CarrierRankingQueryService {
  final List<CarrierPerformanceRank> result;
  _FakeRanking(this.result);
  @override
  Future<List<CarrierPerformanceRank>> getRanking({
    required String organizationId,
    int limit = 20,
  }) async => result;
}

class _FakeFleetRisk implements FleetRiskQueryService {
  final List<FleetRiskWindow> result;
  _FakeFleetRisk(this.result);
  @override
  Future<List<FleetRiskWindow>> listFleetRisk({
    required String organizationId,
    int limit = 10,
  }) async => result;
}

FleetRiskWindow _window(String id, int riskBps) => FleetRiskWindow(
  setId: id,
  contractId: 'c-$id',
  windowStartUtc: DateTime.utc(2026, 6, 1, 8),
  windowEndUtc: DateTime.utc(2026, 6, 1, 10),
  riskBps: riskBps,
  contractualValue: const Money(150000),
);

CarrierPerformanceRank _rank() => const CarrierPerformanceRank(
  organizationId: 'org-1',
  contractId: 'c-1',
  totalObligations: 10,
  executedCount: 8,
  noShowCount: 1,
  evidenceGapCount: 1,
  falsePositiveCount: 0,
  falseNegativeCount: 0,
  complianceRateBps: 8000,
  disputeCount: 2,
  disputeRateBps: 2000,
  fineExposure: Money(150000),
  lastEvaluatedUtc: null,
);

void main() {
  group('analytics providers — unauthenticated short-circuit', () {
    test(
      'carrierRankingProvider returns [] when no org (no infra touched)',
      () async {
        final c = ProviderContainer(
          overrides: [currentOrganizationIdProvider.overrideWithValue(null)],
        );
        addTearDown(c.dispose);
        expect(await c.read(carrierRankingProvider.future), isEmpty);
      },
    );

    test('fleetRiskSummaryProvider returns [] when no org', () async {
      final c = ProviderContainer(
        overrides: [currentOrganizationIdProvider.overrideWithValue(null)],
      );
      addTearDown(c.dispose);
      expect(await c.read(fleetRiskSummaryProvider.future), isEmpty);
    });
  });

  group('analytics providers — wired to query services', () {
    test(
      'carrierRankingProvider yields the service result for the org',
      () async {
        final c = ProviderContainer(
          overrides: [
            currentOrganizationIdProvider.overrideWithValue('org-1'),
            carrierRankingQueryServiceProvider.overrideWithValue(
              _FakeRanking([_rank()]),
            ),
          ],
        );
        addTearDown(c.dispose);
        final rows = await c.read(carrierRankingProvider.future);
        expect(rows, hasLength(1));
      },
    );

    test(
      'fleetRiskSentinelProvider picks the worst (highest riskBps) window',
      () async {
        final c = ProviderContainer(
          overrides: [
            currentOrganizationIdProvider.overrideWithValue('org-1'),
            fleetRiskQueryServiceProvider.overrideWithValue(
              _FakeFleetRisk([
                _window('a', 4000),
                _window('b', 9500),
                _window('c', 8000),
              ]),
            ),
          ],
        );
        addTearDown(c.dispose);
        // Resolve the async summary first so the sentinel has data.
        await c.read(fleetRiskSummaryProvider.future);
        final sentinel = c.read(fleetRiskSentinelProvider);
        expect(sentinel?.setId, 'b');
        expect(sentinel?.riskBps, 9500);
      },
    );

    test(
      'fleetRiskSentinelProvider is null when there are no active windows',
      () async {
        final c = ProviderContainer(
          overrides: [
            currentOrganizationIdProvider.overrideWithValue('org-1'),
            fleetRiskQueryServiceProvider.overrideWithValue(
              _FakeFleetRisk(const []),
            ),
          ],
        );
        addTearDown(c.dispose);
        await c.read(fleetRiskSummaryProvider.future);
        expect(c.read(fleetRiskSentinelProvider), isNull);
      },
    );
  });
}
