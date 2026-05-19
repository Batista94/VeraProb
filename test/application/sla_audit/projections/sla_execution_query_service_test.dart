import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_query_service_in_memory.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

void main() {
  late InMemoryContractualExecutionStateRepository repo;
  late SlaExecutionQueryServiceInMemory queryService;

  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100;

  setUp(() {
    repo = InMemoryContractualExecutionStateRepository();
    queryService = SlaExecutionQueryServiceInMemory(
      repo: repo,
      clock: FakeDateTimeProvider(DateTime.utc(2026, 1, 1)),
    );
  });

  ContractualExecutionState makeState({
    required String setId,
    String contractId = 'c-1',
    DateTime? windowStart,
    DateTime? windowEnd,
    Money contractualValue = const Money(15000),
    int noShowPenaltyBps = 15000,
  }) {
    return ContractualExecutionState.create(
      organizationId: 'org-1',
      setId: setId,
      contractId: contractId,
      planVersion: 1,
      startLatitude: geoLat,
      startLongitude: geoLng,
      startRadiusMeters: geoRadius,
      contractualValue: contractualValue,
      noShowPenaltyBps: noShowPenaltyBps,
      windowStartUtc: windowStart ?? DateTime.utc(2026, 3, 1, 6, 0),
      windowEndUtc: windowEnd ?? DateTime.utc(2026, 3, 1, 7, 0),
    );
  }

  Future<void> seedMixedStates() async {
    // 2 pending
    await repo.save(makeState(setId: 'pending-1'));
    await repo.save(makeState(setId: 'pending-2'));

    // 1 executed
    final executed = makeState(setId: 'executed-1');
    executed.bindExecution(
      vehicleId: 'v-1',
      latitude: geoLat,
      longitude: geoLng,
      timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
    );
    await repo.save(executed);

    // 1 noShow
    final noShow = makeState(
      setId: 'noshow-1',
      windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
    );
    noShow.markFailed(DateTime.utc(2026, 3, 1, 7, 1));
    await repo.save(noShow);

    // 1 completedWithGaps
    final gap = makeState(setId: 'gap-1');
    gap.startTransit(
      timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
      source: 'telegram',
    );
    gap.completeWithGaps(DateTime.utc(2026, 3, 1, 6, 45));
    await repo.save(gap);
  }

  group('SlaExecutionQueryService (in-memory)', () {
    test('getSummary reflects correct counts by status', () async {
      await seedMixedStates();

      final summary = await queryService.getSummary(organizationId: 'org-1');

      expect(summary.totalPlanned, 2);
      expect(summary.totalCompleted, 1);
      expect(summary.totalFailed, 1);
      expect(summary.totalCompletedWithGaps, 1);
      expect(summary.total, 5);
      expect(summary.contractId, isNull);
    });

    test('getSummary filters by contractId', () async {
      await repo.save(makeState(setId: 'c1-1', contractId: 'c-1'));
      await repo.save(makeState(setId: 'c1-2', contractId: 'c-1'));
      await repo.save(makeState(setId: 'c2-1', contractId: 'c-2'));

      final summaryC1 = await queryService.getSummary(
        organizationId: 'org-1',
        contractId: 'c-1',
      );
      expect(summaryC1.totalPlanned, 2);
      expect(summaryC1.total, 2);
      expect(summaryC1.contractId, 'c-1');

      final summaryC2 = await queryService.getSummary(
        organizationId: 'org-1',
        contractId: 'c-2',
      );
      expect(summaryC2.totalPlanned, 1);
      expect(summaryC2.total, 1);
    });

    test('listByStatus returns only matching status', () async {
      await seedMixedStates();

      final pending = await queryService.listByStatus(
        ExecutionStatus.planned,
        organizationId: 'org-1',
      );
      expect(pending, hasLength(2));
      expect(
        pending.every((item) => item.status == ExecutionStatus.planned),
        isTrue,
      );

      final executed = await queryService.listByStatus(
        ExecutionStatus.completed,
        organizationId: 'org-1',
      );
      expect(executed, hasLength(1));
      expect(executed.first.setId, 'executed-1');
      expect(executed.first.boundVehicleId, 'v-1');
    });

    test('listByStatus orders by windowStartUtc ascending', () async {
      await repo.save(
        makeState(
          setId: 'late',
          windowStart: DateTime.utc(2026, 3, 1, 9, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
        ),
      );
      await repo.save(
        makeState(
          setId: 'early',
          windowStart: DateTime.utc(2026, 3, 1, 6, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        ),
      );
      await repo.save(
        makeState(
          setId: 'mid',
          windowStart: DateTime.utc(2026, 3, 1, 7, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 8, 0),
        ),
      );

      final items = await queryService.listByStatus(
        ExecutionStatus.planned,
        organizationId: 'org-1',
      );

      expect(items, hasLength(3));
      expect(items[0].setId, 'early');
      expect(items[1].setId, 'mid');
      expect(items[2].setId, 'late');
    });

    test('finalized and pending states are correctly separated', () async {
      await seedMixedStates();

      final noShowItems = await queryService.listByStatus(
        ExecutionStatus.failed,
        organizationId: 'org-1',
      );
      expect(noShowItems, hasLength(1));
      expect(noShowItems.first.setId, 'noshow-1');

      final gapItems = await queryService.listByStatus(
        ExecutionStatus.completedWithGaps,
        organizationId: 'org-1',
      );
      expect(gapItems, hasLength(1));
      expect(gapItems.first.setId, 'gap-1');

      // Verify read model fields are mapped correctly
      final executedItems = await queryService.listByStatus(
        ExecutionStatus.completed,
        organizationId: 'org-1',
      );
      final item = executedItems.first;
      expect(item.boundAtUtc, isNotNull);
      expect(item.boundVehicleId, 'v-1');
      expect(item.startLatitude, geoLat);
      expect(item.startLongitude, geoLng);
      expect(item.startRadiusMeters, geoRadius);
    });

    test(
      'listByWindow returns states whose windowStart falls in the range',
      () async {
        final t6 = DateTime.utc(2026, 3, 1, 6, 0);
        final t7 = DateTime.utc(2026, 3, 1, 7, 0);
        final t8 = DateTime.utc(2026, 3, 1, 8, 0);
        final t9 = DateTime.utc(2026, 3, 1, 9, 0);

        await repo.save(
          makeState(setId: 'early', windowStart: t6, windowEnd: t7),
        );
        await repo.save(
          makeState(setId: 'mid', windowStart: t7, windowEnd: t8),
        );
        await repo.save(
          makeState(setId: 'late', windowStart: t8, windowEnd: t9),
        );

        // window [t6, t8) should include 'early' and 'mid'
        final items = await queryService.listByWindow(
          t6,
          t8,
          organizationId: 'org-1',
        );
        expect(
          items.map((i) => i.setId).toList(),
          containsAll(['early', 'mid']),
        );
        expect(items.any((i) => i.setId == 'late'), isFalse);
      },
    );

    test('listByWindow respects contractId filter', () async {
      final t6 = DateTime.utc(2026, 3, 1, 6, 0);
      final t7 = DateTime.utc(2026, 3, 1, 7, 0);
      await repo.save(
        makeState(
          setId: 'c1-x',
          contractId: 'c-1',
          windowStart: t6,
          windowEnd: t7,
        ),
      );
      await repo.save(
        makeState(
          setId: 'c2-x',
          contractId: 'c-2',
          windowStart: t6,
          windowEnd: t7,
        ),
      );

      final items = await queryService.listByWindow(
        t6,
        t7.add(const Duration(hours: 1)),
        organizationId: 'org-1',
        contractId: 'c-1',
      );
      expect(items, hasLength(1));
      expect(items.first.setId, 'c1-x');
    });

    test('listByStatus respects contractId filter', () async {
      await repo.save(makeState(setId: 'c1-set', contractId: 'c-1'));
      await repo.save(makeState(setId: 'c2-set', contractId: 'c-2'));

      final items = await queryService.listByStatus(
        ExecutionStatus.planned,
        organizationId: 'org-1',
        contractId: 'c-1',
      );
      expect(items, hasLength(1));
      expect(items.first.setId, 'c1-set');
    });

    test(
      'getSummary calculates financial projections correctly without fall-through',
      () async {
        // 1. Pending: contractualValue = 50.0 → should not affect any revenue
        final pending = makeState(
          setId: 'fin-pending',
          contractualValue: const Money(5000),
          noShowPenaltyBps: 10000,
        );
        await repo.save(pending);

        // 2. Executed: contractualValue = 200.0 → protectedRevenue only
        final executed = makeState(
          setId: 'fin-exec',
          contractualValue: const Money(20000),
          noShowPenaltyBps: 20000,
        );
        executed.bindExecution(
          vehicleId: 'v-1',
          latitude: geoLat,
          longitude: geoLng,
          timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
        );
        await repo.save(executed);

        // 3. NoShow: contractualValue = 100.0, multiplier = 1.5 → lostRevenue = 150 only
        final noShow = makeState(
          setId: 'fin-noshow',
          contractualValue: const Money(10000),
          noShowPenaltyBps: 15000,
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        );
        noShow.markFailed(DateTime.utc(2026, 3, 1, 7, 1));
        await repo.save(noShow);

        // 4. CompletedWithGaps: contractualValue = 80.0 → lostRevenue
        final gap = makeState(
          setId: 'fin-gap',
          contractualValue: const Money(8000),
          noShowPenaltyBps: 10000,
        );
        gap.startTransit(
          timestampUtc: DateTime.utc(2026, 3, 1, 6, 30),
          source: 'telegram',
        );
        gap.completeWithGaps(DateTime.utc(2026, 3, 1, 6, 45));
        await repo.save(gap);

        final summary = await queryService.getSummary(organizationId: 'org-1');

        // Verify counters are isolated
        expect(summary.totalPlanned, 1);
        expect(summary.totalCompleted, 1);
        expect(summary.totalFailed, 1);
        expect(summary.totalCompletedWithGaps, 1);

        // Verify revenues are isolated
        expect(summary.protectedRevenue, 20000);
        expect(
          summary.lostRevenue,
          23000,
        ); // 15000 (noShow) + 8000 (completedWithGaps)
        expect(summary.revenueAtRisk, 0);
      },
    );
  });
}
