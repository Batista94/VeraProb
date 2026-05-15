import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  final periodStart = DateTime.utc(2026, 3, 1);
  final periodEnd = DateTime.utc(2026, 3, 31);
  final closedAt = DateTime.utc(2026, 4, 1, 6, 0, 0);

  ContractualFinancialDailySnapshot makeSnapshot({
    required DateTime date,
    int contractedCents = 100000,
    int protectedCents = 80000,
    int atRiskCents = 15000,
    int lostCents = 5000,
    int totalOb = 10,
    int exec = 8,
    int noShow = 1,
    int gap = 1,
  }) {
    return ContractualFinancialDailySnapshot.create(
      organizationId: 'org-1',
      contractId: 'contract-1',
      operationalDateUtc: date,
      operationalTimezone: 'America/Sao_Paulo',
      closedAtUtc: closedAt,
      totalContractedRevenue: Money(contractedCents),
      protectedRevenue: Money(protectedCents),
      revenueAtRisk: Money(atRiskCents),
      lostRevenue: Money(lostCents),
      totalObligations: totalOb,
      executedCount: exec,
      noShowCount: noShow,
      evidenceGapCount: gap,
      lastLedgerEntryId: 'ledger-entry-1',
      engineVersion: 'veraprob-core_v4-test',
    );
  }

  group('BillingCycleReport.create — financial aggregation', () {
    test('aggregates monetary values from snapshots correctly', () {
      final s1 = makeSnapshot(
        date: DateTime.utc(2026, 3, 1),
        contractedCents: 100000,
        lostCents: 5000,
      );
      final s2 = makeSnapshot(
        date: DateTime.utc(2026, 3, 2),
        contractedCents: 200000,
        lostCents: 10000,
      );

      final report = BillingCycleReport.create(
        organizationId: 'org-1',
        contractId: 'contract-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [s1, s2],
        isComplete: true,
        missingDates: [],
      );

      expect(report.totalContractedRevenue, equals(const Money(300000)));
      expect(report.lostRevenue, equals(const Money(15000)));
      expect(report.organizationId, 'org-1');
    });

    test('aggregates obligation counts correctly', () {
      final s1 = makeSnapshot(
        date: DateTime.utc(2026, 3, 1),
        totalOb: 10,
        exec: 8,
        noShow: 1,
        gap: 1,
      );
      final s2 = makeSnapshot(
        date: DateTime.utc(2026, 3, 2),
        totalOb: 20,
        exec: 15,
        noShow: 3,
        gap: 2,
      );

      final report = BillingCycleReport.create(
        organizationId: 'org-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [s1, s2],
        isComplete: true,
        missingDates: [],
      );

      expect(report.totalObligations, 30);
      expect(report.executedCount, 23);
      expect(report.noShowCount, 4);
      expect(report.evidenceGapCount, 3);
    });

    test(
      'calculates complianceRateBps correctly — 8 of 10 = 8000 bps (80%)',
      () {
        final s = makeSnapshot(
          date: DateTime.utc(2026, 3, 1),
          totalOb: 10,
          exec: 8,
          noShow: 1,
          gap: 1,
        );

        final report = BillingCycleReport.create(
          organizationId: 'org-1',
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          snapshots: [s],
          isComplete: true,
          missingDates: [],
        );

        expect(report.complianceRateBps, 8000);
      },
    );

    test('complianceRateBps is 10000 when zero obligations (no division)', () {
      final report = BillingCycleReport.create(
        organizationId: 'org-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [],
        isComplete: false,
        missingDates: [DateTime.utc(2026, 3, 1)],
      );

      expect(report.complianceRateBps, 10000);
      expect(report.isComplete, isFalse);
    });

    test('id is deterministic — same inputs produce same id', () {
      final snapshots = [makeSnapshot(date: DateTime.utc(2026, 3, 1))];

      final r1 = BillingCycleReport.create(
        organizationId: 'org-1',
        contractId: 'contract-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: snapshots,
        isComplete: true,
        missingDates: [],
        generatedAtUtc: DateTime.utc(2026, 4, 1),
      );
      final r2 = BillingCycleReport.create(
        organizationId: 'org-1',
        contractId: 'contract-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: snapshots,
        isComplete: true,
        missingDates: [],
        generatedAtUtc: DateTime.utc(2026, 4, 1),
      );

      expect(r1.id, equals(r2.id));
    });

    test('id differs when organizationId differs', () {
      final snapshots = [makeSnapshot(date: DateTime.utc(2026, 3, 1))];

      final r1 = BillingCycleReport.create(
        organizationId: 'org-A',
        contractId: 'contract-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: snapshots,
        isComplete: true,
        missingDates: [],
      );
      final r2 = BillingCycleReport.create(
        organizationId: 'org-B',
        contractId: 'contract-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: snapshots,
        isComplete: true,
        missingDates: [],
      );

      expect(r1.id, isNot(equals(r2.id)));
    });

    test('null contractId uses ALL scope in id generation', () {
      final r1 = BillingCycleReport.create(
        organizationId: 'org-1',
        contractId: null,
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [],
        isComplete: true,
        missingDates: [],
      );
      final r2 = BillingCycleReport.create(
        organizationId: 'org-1',
        contractId: 'ALL',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [],
        isComplete: true,
        missingDates: [],
      );

      expect(r1.id, equals(r2.id));
    });

    test('snapshotIds and operationalDates are populated from snapshots', () {
      final s1 = makeSnapshot(date: DateTime.utc(2026, 3, 1));
      final s2 = makeSnapshot(date: DateTime.utc(2026, 3, 2));

      final report = BillingCycleReport.create(
        organizationId: 'org-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [s1, s2],
        isComplete: true,
        missingDates: [],
      );

      expect(report.snapshotIds, containsAll([s1.id, s2.id]));
      expect(report.operationalDates, hasLength(2));
    });

    test('missingDates is stored and isComplete reflects audit flag', () {
      final missing = [DateTime.utc(2026, 3, 15)];

      final report = BillingCycleReport.create(
        organizationId: 'org-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [],
        isComplete: false,
        missingDates: missing,
      );

      expect(report.isComplete, isFalse);
      expect(report.missingDates, contains(DateTime.utc(2026, 3, 15)));
    });

    test('100% compliance: all obligations executed = 10000 bps', () {
      final s = makeSnapshot(
        date: DateTime.utc(2026, 3, 1),
        totalOb: 5,
        exec: 5,
        noShow: 0,
        gap: 0,
      );

      final report = BillingCycleReport.create(
        organizationId: 'org-1',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        snapshots: [s],
        isComplete: true,
        missingDates: [],
      );

      expect(report.complianceRateBps, 10000);
    });
  });
}
