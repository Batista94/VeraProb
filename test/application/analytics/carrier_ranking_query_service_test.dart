import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/analytics/carrier_performance_rank.dart';
import 'package:veraprob/application/analytics/carrier_ranking_query_service.dart';
import 'package:veraprob/domain/shared/money.dart';

/// Contract fake: records the call and echoes a preset ranking.
class _FakeRanking implements CarrierRankingQueryService {
  int? lastLimit;
  String? lastOrg;
  final List<CarrierPerformanceRank> result;
  _FakeRanking(this.result);

  @override
  Future<List<CarrierPerformanceRank>> getRanking({
    required String organizationId,
    int limit = 20,
  }) async {
    lastOrg = organizationId;
    lastLimit = limit;
    return result;
  }
}

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
  group('CarrierRankingQueryService (port contract)', () {
    test('getRanking forwards org and returns the ranking', () async {
      final svc = _FakeRanking([_rank()]);
      final rows = await svc.getRanking(organizationId: 'org-1');
      expect(rows, hasLength(1));
      expect(svc.lastOrg, 'org-1');
    });

    test('default limit is 20 (worst performers page)', () async {
      final svc = _FakeRanking(const []);
      await svc.getRanking(organizationId: 'org-1');
      expect(svc.lastLimit, 20);
      await svc.getRanking(organizationId: 'org-1', limit: 5);
      expect(svc.lastLimit, 5);
    });

    test(
      'CarrierPerformanceRank.fromJson maps rates as bps + Money exposure',
      () {
        final r = CarrierPerformanceRank.fromJson({
          'organization_id': 'org-1',
          'contract_id': 'c-1',
          'total_obligations': 10,
          'executed_count': 8,
          'no_show_count': 1,
          'evidence_gap_count': 1,
          'false_positive_count': 0,
          'false_negative_count': 0,
          'compliance_rate_bps': 8000,
          'dispute_count': 2,
          'dispute_rate_bps': 2000,
          'total_fine_exposure_cents': 150000,
          'last_evaluated_utc': null,
        });
        expect(r.complianceRateBps, 8000);
        expect(r.fineExposure, const Money(150000));
        expect(r.lastEvaluatedUtc, isNull);
      },
    );
  });
}
