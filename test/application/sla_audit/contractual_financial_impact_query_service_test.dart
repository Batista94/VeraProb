import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/sla_audit/projections/contractual_financial_impact_query_service_in_memory.dart';
import 'package:busflow/domain/shared/money.dart';
import 'package:busflow/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';

void main() {
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late ContractualFinancialImpactQueryServiceInMemory queryService;

  setUp(() {
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    queryService = ContractualFinancialImpactQueryServiceInMemory(
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
    );
  }

  group('ContractualFinancialImpactQueryService (snapshot-based)', () {
    test('empty repository returns zero Money values', () async {
      final impact = await queryService.getImpact();

      expect(impact.totalContractedRevenue, const Money(0));
      expect(impact.protectedRevenue, const Money(0));
      expect(impact.revenueAtRisk, const Money(0));
      expect(impact.lostRevenue, const Money(0));
      expect(impact.riskPercentage, 0.0);
      expect(impact.lossPercentage, 0.0);
    });

    test('returns latest snapshot as current impact', () async {
      await snapshotRepo.save(
        makeSnapshot(
          date: DateTime.utc(2026, 3, 1),
          total: Money.fromDouble(1000.0),
          protected_: Money.fromDouble(500.0),
          atRisk: Money.fromDouble(300.0),
          lost: Money.fromDouble(200.0),
        ),
      );

      await snapshotRepo.save(
        makeSnapshot(
          date: DateTime.utc(2026, 3, 2),
          total: Money.fromDouble(2000.0),
          protected_: Money.fromDouble(1500.0),
          atRisk: Money.fromDouble(300.0),
          lost: Money.fromDouble(200.0),
        ),
      );

      final impact = await queryService.getImpact();

      // Should return the latest snapshot (March 2nd)
      expect(impact.totalContractedRevenue, Money.fromDouble(2000.0));
      expect(impact.protectedRevenue, Money.fromDouble(1500.0));
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

      final impactC1 = await queryService.getImpact(contractId: 'c-1');
      expect(impactC1.totalContractedRevenue, Money.fromDouble(100.0));

      final impactC2 = await queryService.getImpact(contractId: 'c-2');
      expect(impactC2.totalContractedRevenue, Money.fromDouble(500.0));
    });
  });
}
