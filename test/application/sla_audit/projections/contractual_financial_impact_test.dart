import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  final now = DateTime.utc(2024, 6, 1);

  ContractualFinancialImpact makeImpact({
    String? contractId,
    int? marginErosionBps,
  }) => ContractualFinancialImpact(
    contractId: contractId,
    generatedAtUtc: now,
    totalContractedRevenue: const Money(1000000),
    protectedRevenue: const Money(700000),
    revenueAtRisk: const Money(200000),
    lostRevenue: const Money(100000),
    riskPercentageBps: 2000,
    lossPercentageBps: 1000,
    marginErosionBps: marginErosionBps,
  );

  group('ContractualFinancialImpact', () {
    test('props equality — same values are equal', () {
      final i1 = makeImpact(contractId: 'c1', marginErosionBps: 500);
      final i2 = makeImpact(contractId: 'c1', marginErosionBps: 500);
      expect(i1, equals(i2));
    });

    test('marginErosionBps null is handled', () {
      final i = makeImpact();
      expect(i.marginErosionBps, isNull);
    });

    test('marginErosionBps non-null is stored', () {
      final i = makeImpact(marginErosionBps: 4250);
      expect(i.marginErosionBps, 4250);
    });

    test('contractId null is handled', () {
      final i = makeImpact();
      expect(i.contractId, isNull);
    });

    test('props inequality — different lossPercentage', () {
      final i1 = makeImpact();
      final i2 = ContractualFinancialImpact(
        generatedAtUtc: now,
        totalContractedRevenue: const Money(1000000),
        protectedRevenue: const Money(700000),
        revenueAtRisk: const Money(200000),
        lostRevenue: const Money(100000),
        riskPercentageBps: 2000,
        lossPercentageBps: 9900, // different
      );
      expect(i1, isNot(equals(i2)));
    });
  });
}
