import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/financial_sparkline_query_service_in_memory.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';

void main() {
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late FinancialSparklineQueryServiceInMemory queryService;

  setUp(() {
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    queryService = FinancialSparklineQueryServiceInMemory(
      snapshotRepo: snapshotRepo,
    );
  });

  ContractualFinancialDailySnapshot makeSnapshot({
    required DateTime date,
    required int totalCents,
    required int protectedCents,
    required int atRiskCents,
    required int lostCents,
  }) {
    return ContractualFinancialDailySnapshot.create(
      organizationId: 'org-1',
      contractId: null,
      operationalDateUtc: date,
      operationalTimezone: 'America/Sao_Paulo',
      closedAtUtc: DateTime.utc(2026, 3, 2, 3),
      totalContractedRevenue: Money(totalCents),
      protectedRevenue: Money(protectedCents),
      revenueAtRisk: Money(atRiskCents),
      lostRevenue: Money(lostCents),
      totalObligations: 10,
      executedCount: 8,
      noShowCount: 1,
      evidenceGapCount: 1,
      lastLedgerEntryId: '100',
      engineVersion: 'veraprob-core_v4-test',
    );
  }

  group('FinancialSparklineQueryServiceInMemory', () {
    test('empty repository returns the empty series (INV-4)', () async {
      final series = await queryService.getSparkline(
        organizationId: 'org-1',
        days: 30,
      );
      expect(series.isEmpty, isTrue);
    });

    test('maps snapshot cents into protected/atRisk/lost series', () async {
      final now = DateTime.now().toUtc();
      await snapshotRepo.save(
        makeSnapshot(
          date: now.subtract(const Duration(days: 2)),
          totalCents: 100000,
          protectedCents: 70000,
          atRiskCents: 20000,
          lostCents: 10000,
        ),
      );

      final series = await queryService.getSparkline(
        organizationId: 'org-1',
        days: 30,
      );

      expect(series.protectedCents, [70000]);
      expect(series.atRiskCents, [20000]);
      expect(series.lostCents, [10000]);
      expect(series.datesUtc, hasLength(1));
    });

    test('orders samples by operational date ascending', () async {
      final now = DateTime.now().toUtc();
      await snapshotRepo.save(
        makeSnapshot(
          date: now.subtract(const Duration(days: 2)),
          totalCents: 100000,
          protectedCents: 200,
          atRiskCents: 0,
          lostCents: 0,
        ),
      );
      await snapshotRepo.save(
        makeSnapshot(
          date: now.subtract(const Duration(days: 5)),
          totalCents: 100000,
          protectedCents: 100,
          atRiskCents: 0,
          lostCents: 0,
        ),
      );

      final series = await queryService.getSparkline(
        organizationId: 'org-1',
        days: 30,
      );

      // Earliest date first: the 5-day-old (100) precedes the 2-day-old (200).
      expect(series.protectedCents, [100, 200]);
      expect(series.datesUtc.first.isBefore(series.datesUtc.last), isTrue);
    });

    test('excludes snapshots older than the requested window', () async {
      final now = DateTime.now().toUtc();
      await snapshotRepo.save(
        makeSnapshot(
          date: now.subtract(const Duration(days: 2)),
          totalCents: 100000,
          protectedCents: 999,
          atRiskCents: 0,
          lostCents: 0,
        ),
      );
      await snapshotRepo.save(
        makeSnapshot(
          date: now.subtract(const Duration(days: 40)),
          totalCents: 100000,
          protectedCents: 111,
          atRiskCents: 0,
          lostCents: 0,
        ),
      );

      final series = await queryService.getSparkline(
        organizationId: 'org-1',
        days: 30,
      );

      expect(series.protectedCents, [999]);
    });
  });
}
