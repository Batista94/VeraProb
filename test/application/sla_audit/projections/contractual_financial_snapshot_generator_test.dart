import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:veraprob/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:veraprob/core/time/brazil_time.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  late InMemoryContractualExecutionStateRepository executionRepo;
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late InMemorySlaAuditLedgerRepository ledgerRepo;
  late ContractualFinancialSnapshotGenerator generator;

  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100;

  setUp(() {
    tz.initializeTimeZones();
    BrazilTime.ensureInitialized();
    executionRepo = InMemoryContractualExecutionStateRepository();
    snapshotRepo = InMemoryContractualFinancialSnapshotRepository();
    ledgerRepo = InMemorySlaAuditLedgerRepository();
    generator = ContractualFinancialSnapshotGenerator(
      executionRepo: executionRepo,
      snapshotRepo: snapshotRepo,
      ledgerRepo: ledgerRepo,
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

    test('generates correct snapshot for executed states', () async {
      // windowStartUtc 2026-03-01 09:00 UTC = 2026-03-01 06:00 BRT (same day)
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
      // Pending
      await executionRepo.save(
        makeState(
          setId: 'pending-1',
          contractualValue: const Money(20000),
          windowStart: DateTime.utc(2026, 3, 1, 9, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 10, 0),
        ),
      );

      // Executed
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

      // NoShow
      final noShow = makeState(
        setId: 'noshow-1',
        contractualValue: const Money(10000),
        noShowPenaltyBps: 15000,
        windowStart: DateTime.utc(2026, 3, 1, 13, 0),
        windowEnd: DateTime.utc(2026, 3, 1, 14, 0),
      );
      noShow.markNoShow(DateTime.utc(2026, 3, 1, 14, 1));
      await executionRepo.save(noShow);

      await generator.generateDailySnapshot('org-1', DateTime.utc(2026, 3, 1));

      final snapshots = await snapshotRepo.findAll(organizationId: 'org-1');
      expect(snapshots, hasLength(1));

      final s = snapshots.first;
      expect(s.totalContractedRevenue, const Money(60000));
      expect(s.protectedRevenue, const Money(30000));
      expect(s.revenueAtRisk, const Money(20000));
      expect(s.lostRevenue, const Money(15000)); // 100 * 1.5
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
