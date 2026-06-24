import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/analytics/carrier_performance_rank.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  Map<String, dynamic> row() => {
    'organization_id': 'org-1',
    'contract_id': 'contractA',
    'total_obligations': 10,
    'executed_count': 8,
    'no_show_count': 1,
    'evidence_gap_count': 1,
    'false_positive_count': 1,
    'false_negative_count': 0,
    'compliance_rate_bps': 8000,
    'dispute_count': 2,
    'dispute_rate_bps': 2000,
    'total_fine_exposure_cents': 90000,
    'last_evaluated_utc': '2026-06-14T10:00:00+00:00',
  };

  group('CarrierPerformanceRank.fromJson', () {
    test('maps every projected column', () {
      final r = CarrierPerformanceRank.fromJson(row());
      expect(r.contractId, 'contractA');
      expect(r.totalObligations, 10);
      expect(r.executedCount, 8);
      expect(r.complianceRateBps, 8000);
      expect(r.disputeCount, 2);
      expect(r.disputeRateBps, 2000);
      expect(r.fineExposure, const Money(90000));
      expect(r.lastEvaluatedUtc!.isUtc, isTrue);
    });

    test('tolerates null last_evaluated_utc', () {
      final j = row()..['last_evaluated_utc'] = null;
      expect(CarrierPerformanceRank.fromJson(j).lastEvaluatedUtc, isNull);
    });

    test('Equatable identity over all fields', () {
      expect(
        CarrierPerformanceRank.fromJson(row()),
        equals(CarrierPerformanceRank.fromJson(row())),
      );
    });
  });
}
