import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_impact_query_service_in_memory.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';
import '../../../mocks/fake_date_time_provider.dart';

void main() {
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late ContractualFinancialImpactQueryServiceInMemory queryService;

  setUp(() {
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    queryService = ContractualFinancialImpactQueryServiceInMemory(
      snapshotRepo: snapshotRepo,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 1, 1)),
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
      organizationId: 'org-1',
      contractId: contractId,
      operationalDateUtc: date,
      operationalTimezone: 'America/Sao_Paulo',
      closedAtUtc: DateTime.utc(2026, 3, 2, 3, 0),
      totalContractedRevenue: total,
      protectedRevenue: protected_,
      revenueAtRisk: const Money(300000), // 30 in risk
      lostRevenue: const Money(100000), // 10 lost
      totalObligations: 10,
      executedCount: 7,
      noShowCount: 1,
      evidenceGapCount: 2,
      lastLedgerEntryId: '100',
      engineVersion: 'veraprob-core_v4-test',
    );
  }

  group('ContractualFinancialImpactQueryService (snapshot-based)', () {
    test('empty repository returns zero Money values', () async {
      final impact = await queryService.getImpact(organizationId: 'org-1');

      expect(impact.totalContractedRevenue, 0);
      expect(impact.protectedRevenue, 0);
      expect(impact.revenueAtRisk, 0);
      expect(impact.lostRevenue, 0);
      expect(impact.riskPercentageBps, 0);
      expect(impact.lossPercentageBps, 0);
    });

    test('returns latest snapshot as current impact', () async {
      await snapshotRepo.save(
        makeSnapshot(
          date: DateTime.utc(2026, 3, 1),
          total: const Money(100000),
          protected_: const Money(50000),
          atRisk: const Money(30000),
          lost: const Money(20000),
        ),
      );

      await snapshotRepo.save(
        makeSnapshot(
          date: DateTime.utc(2026, 3, 2),
          total: const Money(200000),
          protected_: const Money(150000),
          atRisk: const Money(30000),
          lost: const Money(20000),
        ),
      );

      final impact = await queryService.getImpact(organizationId: 'org-1');

      // Should return the latest snapshot (March 2nd)
      expect(impact.totalContractedRevenue, 200000);
      expect(impact.protectedRevenue, 150000);
    });

    test('filters by contractId', () async {
      await snapshotRepo.save(
        makeSnapshot(
          contractId: 'c-1',
          date: DateTime.utc(2026, 3, 1),
          total: const Money(10000),
          protected_: const Money(10000),
          atRisk: const Money(0),
          lost: const Money(0),
        ),
      );

      await snapshotRepo.save(
        makeSnapshot(
          contractId: 'c-2',
          date: DateTime.utc(2026, 3, 1),
          total: const Money(50000),
          protected_: const Money(50000),
          atRisk: const Money(0),
          lost: const Money(0),
        ),
      );

      final impactC1 = await queryService.getImpact(
        organizationId: 'org-1',
        contractId: 'c-1',
      );
      expect(impactC1.totalContractedRevenue, 10000);

      final impactC2 = await queryService.getImpact(
        organizationId: 'org-1',
        contractId: 'c-2',
      );
      expect(impactC2.totalContractedRevenue, 50000);
    });
  });
}
