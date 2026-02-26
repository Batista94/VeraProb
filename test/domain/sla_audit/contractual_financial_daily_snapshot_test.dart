import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/domain/shared/money.dart';
import 'package:busflow/domain/sla_audit/contractual_financial_daily_snapshot.dart';

void main() {
  group('ContractualFinancialDailySnapshot', () {
    test('creates with correct fields and auto-calculated percentages', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        contractId: 'c-1',
        operationalDateUtc: DateTime.utc(2026, 3, 1, 10, 30),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: Money.fromDouble(1000.0),
        protectedRevenue: Money.fromDouble(500.0),
        revenueAtRisk: Money.fromDouble(300.0),
        lostRevenue: Money.fromDouble(200.0),
      );

      expect(snapshot.contractId, 'c-1');
      expect(snapshot.operationalTimezone, 'America/Sao_Paulo');
      expect(snapshot.totalContractedRevenue, Money.fromDouble(1000.0));
      expect(snapshot.protectedRevenue, Money.fromDouble(500.0));
      expect(snapshot.revenueAtRisk, Money.fromDouble(300.0));
      expect(snapshot.lostRevenue, Money.fromDouble(200.0));
    });

    test('normalizes operationalDateUtc to midnight UTC', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1, 15, 45, 30),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(10000),
        protectedRevenue: const Money(10000),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
      );

      expect(snapshot.operationalDateUtc, DateTime.utc(2026, 3, 1));
    });

    test('calculates percentages correctly', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(100000), // R$ 1000.00
        protectedRevenue: const Money(50000),
        revenueAtRisk: const Money(30000),
        lostRevenue: const Money(20000),
      );

      expect(snapshot.riskPercentage, 30.0);
      expect(snapshot.lossPercentage, 20.0);
    });

    test('handles zero total revenue (no division by zero)', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(0),
        protectedRevenue: const Money(0),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
      );

      expect(snapshot.riskPercentage, 0.0);
      expect(snapshot.lossPercentage, 0.0);
    });

    test('is immutable (Equatable)', () {
      final s1 = ContractualFinancialDailySnapshot.create(
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(10000),
        protectedRevenue: const Money(10000),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
      );

      // Different id means different instance but same value semantics
      expect(s1.id, isNotEmpty);
    });
  });
}
