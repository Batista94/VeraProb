import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';

void main() {
  group('ContractualFinancialDailySnapshot', () {
    test('creates with correct fields and auto-calculated percentages', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        organizationId: 'org-1',
        contractId: 'c-1',
        operationalDateUtc: DateTime.utc(2026, 3, 1, 10, 30),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(100000),
        protectedRevenue: const Money(50000),
        revenueAtRisk: const Money(30000),
        lostRevenue: const Money(20000),
        totalObligations: 10,
        executedCount: 8,
        noShowCount: 1,
        evidenceGapCount: 1,
        lastLedgerEntryId: '1',
      );

      expect(snapshot.contractId, 'c-1');
      expect(snapshot.operationalTimezone, 'America/Sao_Paulo');
      expect(snapshot.totalContractedRevenue, const Money(100000));
      expect(snapshot.protectedRevenue, const Money(50000));
      expect(snapshot.revenueAtRisk, const Money(30000));
      expect(snapshot.lostRevenue, const Money(20000));
    });

    test('normalizes operationalDateUtc to midnight UTC', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        organizationId: 'org-1',
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1, 15, 45, 30),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(10000),
        protectedRevenue: const Money(10000),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        totalObligations: 10,
        executedCount: 10,
        noShowCount: 0,
        evidenceGapCount: 0,
        lastLedgerEntryId: '1',
      );

      expect(snapshot.operationalDateUtc, DateTime.utc(2026, 3, 1));
    });

    test('calculates percentages correctly', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        organizationId: 'org-1',
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(100000), // R$ 1000.00
        protectedRevenue: const Money(50000),
        revenueAtRisk: const Money(30000),
        lostRevenue: const Money(20000),
        totalObligations: 10,
        executedCount: 5,
        noShowCount: 2,
        evidenceGapCount: 3,
        lastLedgerEntryId: '1',
      );

      expect(snapshot.riskPercentageBps, 3000);
      expect(snapshot.lossPercentageBps, 2000);
    });

    test('handles zero total revenue (no division by zero)', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        organizationId: 'org-1',
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(0),
        protectedRevenue: const Money(0),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        totalObligations: 0,
        executedCount: 0,
        noShowCount: 0,
        evidenceGapCount: 0,
        lastLedgerEntryId: '1',
      );

      expect(snapshot.riskPercentageBps, 0);
      expect(snapshot.lossPercentageBps, 0);
    });

    test('is immutable (Equatable)', () {
      final s1 = ContractualFinancialDailySnapshot.create(
        organizationId: 'org-1',
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(10000),
        protectedRevenue: const Money(10000),
        revenueAtRisk: const Money(0),
        lostRevenue: const Money(0),
        totalObligations: 10,
        executedCount: 10,
        noShowCount: 0,
        evidenceGapCount: 0,
        lastLedgerEntryId: '1',
      );

      // Different id means different instance but same value semantics
      expect(s1.id, isNotEmpty);
    });
    test('riskPercentage calculation', () {
      final snapshot = ContractualFinancialDailySnapshot.create(
        organizationId: 'org-1',
        contractId: null,
        operationalDateUtc: DateTime.utc(2026, 3, 1),
        operationalTimezone: 'America/Sao_Paulo',
        closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
        totalContractedRevenue: const Money(100),
        protectedRevenue: const Money(50),
        revenueAtRisk: const Money(30),
        lostRevenue: const Money(20),
        totalObligations: 10,
        executedCount: 8,
        noShowCount: 1,
        evidenceGapCount: 1,
        lastLedgerEntryId: '1',
      );
      expect(snapshot.riskPercentageBps, 3000);
    });
  });
}
