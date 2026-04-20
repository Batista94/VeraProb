import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_trend_point.dart';

void main() {
  final d1 = DateTime.utc(2024, 6, 1);
  final d2 = DateTime.utc(2024, 6, 2);

  ContractualFinancialTrendPoint makePoint(
    DateTime date,
  ) => ContractualFinancialTrendPoint(
    dateUtc: date,
    formattedDate:
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}',
    baseRevenueUsedForCalculation: 500000,
    totalContractedRevenue: 1000000,
    protectedRevenue: 600000,
    revenueAtRisk: 300000,
    lostRevenue: 100000,
    riskPercentageBps: 3000,
    lossPercentageBps: 1000,
  );

  group('ContractualFinancialTrendPoint', () {
    test('props equality — same values', () {
      final p1 = makePoint(d1);
      final p2 = makePoint(d1);
      expect(p1, equals(p2));
    });

    test('props inequality — different date', () {
      final p1 = makePoint(d1);
      final p2 = makePoint(d2);
      expect(p1, isNot(equals(p2)));
    });

    test('all 9 props fields are stored correctly', () {
      final p = makePoint(d1);
      expect(p.dateUtc, d1);
      expect(p.formattedDate, '01/06');
      expect(p.baseRevenueUsedForCalculation, 500000);
      expect(p.totalContractedRevenue, 1000000);
      expect(p.protectedRevenue, 600000);
      expect(p.revenueAtRisk, 300000);
      expect(p.lostRevenue, 100000);
      expect(p.riskPercentageBps, 3000);
      expect(p.lossPercentageBps, 1000);
    });
  });
}
