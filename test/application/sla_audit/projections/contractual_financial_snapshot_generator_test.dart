import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:veraprob/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:veraprob/domain/shared/brazil_time.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import '../../../mocks/fake_date_time_provider.dart';

void main() {
  late InMemoryContractualExecutionStateRepository executionRepo;
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late InMemorySlaAuditLedgerRepository ledgerRepo;
  late ContractualFinancialSnapshotGenerator generator;
  late FakeDateTimeProvider clock;

  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100;
  const testEngineVersion = 'veraprob-core_v4';

  setUp(() {
    tz.initializeTimeZones();
    BrazilTime.ensureInitialized();
    clock = FakeDateTimeProvider(DateTime.utc(2026, 3, 2, 12, 0));
    executionRepo = InMemoryContractualExecutionStateRepository();
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    ledgerRepo = InMemorySlaAuditLedgerRepository();
    generator = ContractualFinancialSnapshotGenerator(
      executionRepo: executionRepo,
      snapshotRepo: snapshotRepo,
      ledgerRepo: ledgerRepo,
      clock: clock,
      engineVersion: testEngineVersion,
    );
  });

  ContractualExecutionState makeState({
    required String setId,
    String contractId = 'c-1',
    Money contractualValue = const Money(10000),
    int noShowPenaltyBps = 15000,
    required DateTime windowStart,
    required DateTime windowEnd,
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
      windowStartUtc: windowStart,
      windowEndUtc: windowEnd,
    );
  }

  group('ContractualFinancialSnapshotGenerator', () {
    test('empty repo generates snapshot with zero values', () async {
      await generator.generateDailySnapshot('org-1', DateTime.utc(2026, 3, 1));

      final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
      expect(snapshots, hasLength(1));

      final s = snapshots.first;
      expect(s.totalContractedRevenue, const Money(0));
      expect(s.protectedRevenue, const Money(0));
      expect(s.revenueAtRisk, const Money(0));
      expect(s.lostRevenue, const Money(0));
    });

    test(
      '[INV-21] generated snapshot records injected engineVersion',
      () async {
        await generator.generateDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
        );

        final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
        expect(snapshots.first.engineVersion, testEngineVersion);
      },
    );

    test('generates correct snapshot for executed states', () async {
      final exec = makeState(
        setId: 'exec-1',
        contractualValue: const Money(50000),
        windowStart: DateTime.utc(2026, 3, 1, 9, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
      );
      exec.bindExecution(
        vehicleId: 'v-1',
        latitude: geoLat,
        longitude: geoLng,
        timestampUtc: DateTime.utc(2026, 3, 1, 9, 30),
      );
      await executionRepo.save(exec);

      await generator.generateDailySnapshot('org-1', DateTime.utc(2026, 3, 1));

      final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
      expect(snapshots, hasLength(1));
      expect(snapshots.first.protectedRevenue, const Money(50000));
    });

    test('generates correct snapshot for mixed statuses', () async {
      await executionRepo.save(
        makeState(
          setId: 'pending-1',
          contractualValue: const Money(20000),
          windowStart: DateTime.utc(2026, 3, 1, 9, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
        ),
      );

      final exec = makeState(
        setId: 'exec-1',
        contractualValue: const Money(30000),
        windowStart: DateTime.utc(2026, 3, 1, 11, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 12, 0),
      );
      exec.bindExecution(
        vehicleId: 'v-1',
        latitude: geoLat,
        longitude: geoLng,
        timestampUtc: DateTime.utc(2026, 3, 1, 11, 30),
      );
      await executionRepo.save(exec);

      final noShow = makeState(
        setId: 'noshow-1',
        contractualValue: const Money(10000),
        noShowPenaltyBps: 15000,
        windowStart: DateTime.utc(2026, 3, 1, 13, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 14, 0),
      );
      noShow.markFailed(DateTime.utc(2026, 3, 1, 14, 1));
      await executionRepo.save(noShow);

      await generator.generateDailySnapshot('org-1', DateTime.utc(2026, 3, 1));

      final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
      final s = snapshots.first;
      expect(s.totalContractedRevenue, const Money(60000));
      expect(s.protectedRevenue, const Money(30000));
      expect(s.revenueAtRisk, const Money(20000));
      expect(s.lostRevenue, const Money(15000));
    });

    test('is idempotent (does not create duplicate snapshots)', () async {
      await executionRepo.save(
        makeState(
          setId: 'a',
          contractualValue: const Money(10000),
          windowStart: DateTime.utc(2026, 3, 1, 9, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
        ),
      );

      await generator.generateDailySnapshot('org-1', DateTime.utc(2026, 3, 1));
      await generator.generateDailySnapshot('org-1', DateTime.utc(2026, 3, 1));

      final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
      expect(snapshots, hasLength(1));
    });

    test(
      'reprocessDailySnapshot produces identical aggregates to generateDailySnapshot',
      () async {
        final state = makeState(
          setId: 's1',
          contractualValue: const Money(10000),
          windowStart: DateTime.utc(2026, 3, 1, 9, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
        );
        await executionRepo.save(state);

        // 1. Generate first
        await generator.generateDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
        );
        final first = (await snapshotRepo.findAll(
          organizationId: 'org-1',
        )).first;

        // 2. Reprocess
        await generator.reprocessDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
          previousSnapshotId: first.id,
          reprocessingReason: 'manual correction',
          authorUserId: 'u-1',
        );

        final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
        expect(
          snapshots,
          hasLength(1),
        ); // Repository.findAll handles chaining and returns only the active one

        final active = snapshots.first;
        expect(active.id, isNot(first.id));
        expect(active.previousSnapshotId, first.id);
        expect(active.totalContractedRevenue, first.totalContractedRevenue);
        expect(active.protectedRevenue, first.protectedRevenue);
        expect(active.engineVersion, first.engineVersion);
      },
    );

    test(
      '[INV-33] prevents duplicate reprocessing of the same snapshot',
      () async {
        final state = makeState(
          setId: 's1',
          windowStart: DateTime.utc(2026, 3, 1, 9, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
        );
        await executionRepo.save(state);

        await generator.generateDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
        );
        final first = (await snapshotRepo.findAll(
          organizationId: 'org-1',
        )).first;

        // 1. First reprocess: OK
        await generator.reprocessDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
          previousSnapshotId: first.id,
          reprocessingReason: 'first correction',
          authorUserId: 'u-1',
        );

        // 2. Second reprocess of the SAME source: Fail (INV-33)
        final secondReprocess = generator.reprocessDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
          previousSnapshotId: first.id, // SAME ID
          reprocessingReason: 'illegal duplicate correction',
          authorUserId: 'u-1',
        );

        expect(
          secondReprocess,
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('already been superseded'),
            ),
          ),
        );
      },
    );

    test(
      '[INV-33] blocks illegal branch from snapshot superseded deep in chain',
      () async {
        // Chain: A → B → C. Attempting to branch from A (D from A) must fail
        // even though A is not a head — the old findAll-based guard missed this.
        await generator.generateDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
        );
        final snapshotA = (await snapshotRepo.findAll(
          organizationId: 'org-1',
        )).first;

        await generator.reprocessDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
          previousSnapshotId: snapshotA.id,
          reprocessingReason: 'first correction',
          authorUserId: 'u-1',
        );
        final snapshotB = (await snapshotRepo.findAll(
          organizationId: 'org-1',
        )).first;

        await generator.reprocessDailySnapshot(
          'org-1',
          DateTime.utc(2026, 3, 1),
          previousSnapshotId: snapshotB.id,
          reprocessingReason: 'second correction',
          authorUserId: 'u-1',
        );

        // A is now two levels deep and not a head — guard must still block it
        expect(
          generator.reprocessDailySnapshot(
            'org-1',
            DateTime.utc(2026, 3, 1),
            previousSnapshotId: snapshotA.id,
            reprocessingReason: 'illegal branch attempt',
            authorUserId: 'u-1',
          ),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('already been superseded'),
            ),
          ),
        );
      },
    );

    test('filters by contractId', () async {
      await executionRepo.save(
        makeState(
          setId: 'c1-1',
          contractId: 'c-1',
          contractualValue: const Money(10000),
          windowStart: DateTime.utc(2026, 3, 1, 9, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
        ),
      );
      await executionRepo.save(
        makeState(
          setId: 'c2-1',
          contractId: 'c-2',
          contractualValue: const Money(50000),
          windowStart: DateTime.utc(2026, 3, 1, 9, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
        ),
      );

      await generator.generateDailySnapshot(
        'org-1',
        DateTime.utc(2026, 3, 1),
        contractId: 'c-1',
      );

      final snapshots = await snapshotRepo.findAll(
        organizationId: 'org-1',
        contractId: 'c-1',
      );
      expect(snapshots, hasLength(1));
      expect(snapshots.first.totalContractedRevenue, const Money(10000));
    });
  });
}
