import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  final now = DateTime.utc(2024, 6, 1);

  ContractualFinancialImpact makeImpact({
    String? contractId,
    double? marginErosionPercent,
  }) => ContractualFinancialImpact(
    contractId: contractId,
    generatedAtUtc: now,
    totalContractedRevenue: const Money(1000000),
    protectedRevenue: const Money(700000),
    revenueAtRisk: const Money(200000),
    lostRevenue: const Money(100000),
    riskPercentage: 20.0,
    lossPercentage: 10.0,
    marginErosionPercent: marginErosionPercent,
  );

  group('ContractualFinancialImpact', () {
    test('props equality — same values are equal', () {
      final i1 = makeImpact(contractId: 'c1', marginErosionPercent: 5.0);
      final i2 = makeImpact(contractId: 'c1', marginErosionPercent: 5.0);
      expect(i1, equals(i2));
    });

    test('marginErosionPercent null is handled', () {
      final i = makeImpact();
      expect(i.marginErosionPercent, isNull);
    });

    test('marginErosionPercent non-null is stored', () {
      final i = makeImpact(marginErosionPercent: 42.5);
      expect(i.marginErosionPercent, 42.5);
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
        riskPercentage: 20.0,
        lossPercentage: 99.0, // different
      );
      expect(i1, isNot(equals(i2)));
    });
  });
}
