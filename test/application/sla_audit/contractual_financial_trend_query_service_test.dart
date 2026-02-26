import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:busflow/application/sla_audit/projections/contractual_financial_trend_query_service_in_memory.dart';
import 'package:busflow/domain/shared/money.dart';
import 'package:busflow/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';

void main() {
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late ContractualFinancialTrendQueryServiceInMemory queryService;

  setUp(() async {
    await initializeDateFormatting('pt_BR', null);
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    queryService = ContractualFinancialTrendQueryServiceInMemory(
      snapshotRepo: snapshotRepo,
    );
  });

  ContractualFinancialDailySnapshot makeSnapshot({
    String? contractId,
    required DateTime date,
    required Money total,
    required Money protected_,
    required Money atRisk,
    required Money lost,
  }) {
    return ContractualFinancialDailySnapshot.create(
      contractId: contractId,
      operationalDateUtc: date,
      operationalTimezone: 'America/Sao_Paulo',
      closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
      totalContractedRevenue: total,
      protectedRevenue: protected_,
      revenueAtRisk: atRisk,
      lostRevenue: lost,
      lastLedgerEntryId: 1,
    );
  }

  group('ContractualFinancialTrendQueryService (snapshot-based)', () {
    test('empty repository returns empty list', () async {
      final trend = await queryService.getTrend();
      expect(trend, isEmpty);
    });

    test('single snapshot returns one trend point', () async {
      await snapshotRepo.save(
        makeSnapshot(
          date: DateTime.utc(2026, 3, 1),
          total: Money.fromDouble(500.0),
          protected_: Money.fromDouble(300.0),
          atRisk: Money.fromDouble(200.0),
          lost: const Money(0),
        ),
      );

      final trend = await queryService.getTrend();
      expect(trend, hasLength(1));

      final point = trend.first;
      expect(point.formattedDate, '01/03/2026');
      expect(point.totalContractedRevenue, Money.fromDouble(500.0));
      expect(point.baseRevenueUsedForCalculation, Money.fromDouble(500.0));
    });

    test('multiple snapshots are sorted by date ascending', () async {
      await snapshotRepo.save(
        makeSnapshot(
          date: DateTime.utc(2026, 3, 2),
          total: Money.fromDouble(200.0),
          protected_: Money.fromDouble(200.0),
          atRisk: const Money(0),
          lost: const Money(0),
        ),
      );

      await snapshotRepo.save(
        makeSnapshot(
          date: DateTime.utc(2026, 3, 1),
          total: Money.fromDouble(100.0),
          protected_: Money.fromDouble(100.0),
          atRisk: const Money(0),
          lost: const Money(0),
        ),
      );

      final trend = await queryService.getTrend();
      expect(trend, hasLength(2));
      expect(trend[0].formattedDate, '01/03/2026');
      expect(trend[1].formattedDate, '02/03/2026');
    });

    test('filters by contractId', () async {
      await snapshotRepo.save(
        makeSnapshot(
          contractId: 'c-1',
          date: DateTime.utc(2026, 3, 1),
          total: Money.fromDouble(100.0),
          protected_: Money.fromDouble(100.0),
          atRisk: const Money(0),
          lost: const Money(0),
        ),
      );

      await snapshotRepo.save(
        makeSnapshot(
          contractId: 'c-2',
          date: DateTime.utc(2026, 3, 1),
          total: Money.fromDouble(500.0),
          protected_: Money.fromDouble(500.0),
          atRisk: const Money(0),
          lost: const Money(0),
        ),
      );

      final trendC1 = await queryService.getTrend(contractId: 'c-1');
      expect(trendC1, hasLength(1));
      expect(trendC1.first.totalContractedRevenue, Money.fromDouble(100.0));
    });
  });
}
