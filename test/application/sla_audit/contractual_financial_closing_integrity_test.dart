import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:veraprob/application/sla_audit/contractual_financial_closing_service.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:veraprob/domain/shared/brazil_time.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_financial_snapshot_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

void main() {
  late InMemoryContractualExecutionStateRepository executionRepo;
  late InMemoryContractualFinancialSnapshotRepository snapshotRepo;
  late InMemorySlaAuditLedgerRepository ledgerRepo;
  late ContractualFinancialSnapshotGenerator generator;
  late ContractualFinancialClosingService closingService;
  late FakeDateTimeProvider clock;

  const String orgId = 'org-fintech-audit';
  final DateTime operationalDay = DateTime.utc(2026, 3, 1);

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
      engineVersion: 'veraprob-core_v4-test',
    );
    closingService = ContractualFinancialClosingService(generator: generator);
  });

  group('ContractualFinancialClosingService - Financial Integrity (Auditable)', () {
    test(
      'Zero Double Rule & BPS Precision: Validates (valor * bps) ~/ 10000',
      () async {
        // Scenario: 1 BPS penalty on 1,000,000 cents (R$ 10.000,00)
        // Calculation: (1000000 * 1) ~/ 10000 = 100 cents (R$ 1,00)
        final state1Bps = ContractualExecutionState.reconstitute(
          id: 'exe-1bps',
          organizationId: orgId,
          setId: 'set-1',
          contractId: 'con-1',
          planVersion: 1,
          startLatitude: 0,
          startLongitude: 0,
          startRadiusMeters: 100,
          contractualValue: const Money(1000000),
          noShowPenaltyBps: 1,
          windowStartUtc: operationalDay.add(const Duration(hours: 10)),
          windowEndUtc: operationalDay.add(const Duration(hours: 11)),
          status: ExecutionStatus.failed,
          createdAtUtc: operationalDay,
          lastEvaluatedAtUtc: operationalDay,
          statusLastUpdatedAtUtc: operationalDay,
        );

        await executionRepo.save(state1Bps);

        await generator.generateDailySnapshot(orgId, operationalDay);

        final snapshot = (await snapshotRepo.findAll(
          organizationId: orgId,
        )).first;

        // (1000000 * 1) ~/ 10000 = 100
        expect(
          snapshot.lostRevenue.cents,
          equals(100),
          reason: '1 BPS of 1M cents must be exactly 100 cents',
        );
      },
    );

    test(
      'The Penny Drift Test: 1,000 items with 1 cent penalty each must equal 1,000 cents',
      () async {
        // Requirement: Simula um fechamento com 1.000 itens de SLA, cada um com uma multa de 1 centavo.
        // To get 1 cent penalty from multiplyByBps(bps), if value is 100 cents:
        // (100 * bps) ~/ 10000 = 1 => 100 * bps >= 10000 => bps >= 100.
        // So 100 BPS (1%) of 100 cents (R$ 1,00) is 1 cent.

        final List<ContractualExecutionState> states = List.generate(1000, (i) {
          return ContractualExecutionState.reconstitute(
            id: 'drift-$i',
            organizationId: orgId,
            setId: 'set-drift-$i', // Fixed: Unique setId per item
            contractId: 'con-drift',
            planVersion: 1,
            startLatitude: 0,
            startLongitude: 0,
            startRadiusMeters: 100,
            contractualValue: const Money(100), // R$ 1,00
            noShowPenaltyBps: 100, // 1% penalty = 1 cent
            // Base: 12:00 UTC (09:00 BRT) + i seconds (safe within the day)
            windowStartUtc: operationalDay
                .add(const Duration(hours: 12))
                .add(Duration(seconds: i)),
            windowEndUtc: operationalDay
                .add(const Duration(hours: 13))
                .add(Duration(seconds: i)),
            status: ExecutionStatus.failed,
            createdAtUtc: operationalDay,
            lastEvaluatedAtUtc: operationalDay,
            statusLastUpdatedAtUtc: operationalDay,
          );
        });

        for (var s in states) {
          await executionRepo.save(s);
        }

        await generator.generateDailySnapshot(orgId, operationalDay);

        final snapshot = (await snapshotRepo.findAll(
          organizationId: orgId,
        )).first;

        expect(
          snapshot.lostRevenue.cents,
          equals(1000),
          reason:
              'Accumulation of 1,000 individual 1-cent penalties must be exactly 1,000 cents (No Penny Drift)',
        );
      },
    );

    test(
      'Tax/Fee Rounding: 1500 BPS on R\$ 10,01 (1001 cents) follows integer division',
      () async {
        // Requirement: Taxa administrativa de 15% (1500 BPS) sobre R$ 10,01.
        // Logic: (1001 * 1500) ~/ 10000 = 1501500 ~/ 10000 = 150.

        final stateTax = ContractualExecutionState.reconstitute(
          id: 'exe-tax',
          organizationId: orgId,
          setId: 'set-1',
          contractId: 'con-1',
          planVersion: 1,
          startLatitude: 0,
          startLongitude: 0,
          startRadiusMeters: 100,
          contractualValue: const Money(1001),
          noShowPenaltyBps: 1500, // 15%
          windowStartUtc: operationalDay.add(const Duration(hours: 10)),
          windowEndUtc: operationalDay.add(const Duration(hours: 11)),
          status: ExecutionStatus.failed,
          createdAtUtc: operationalDay,
          lastEvaluatedAtUtc: operationalDay,
          statusLastUpdatedAtUtc: operationalDay,
        );

        await executionRepo.save(stateTax);

        await generator.generateDailySnapshot(orgId, operationalDay);

        final snapshot = (await snapshotRepo.findAll(
          organizationId: orgId,
        )).first;

        expect(
          snapshot.lostRevenue.cents,
          equals(150),
          reason:
              '15% of 1001 cents must be 150 cents due to integer division truncation',
        );
      },
    );

    test(
      'UTC Audit Guard: closedAtUtc must be exactly equal to injected timestamp (Identity Match)',
      () async {
        // Requirement: Validar que closedAtUtc é exatamente igual ao tempo injetado, sem drift.
        final DateTime injectedNow = DateTime.utc(
          2026,
          4,
          7,
          12,
          0,
          0,
          123,
        ); // With milliseconds

        // We need to trigger this via the service to test the full chain
        // First call to record current day
        await closingService.onTick(orgId);

        // We don't have control over the internal BrazilTime.nowBrazil() for day transition testing
        // but we refactored generateDailySnapshot and onTick to accept closedAtUtc.
        // Manual trigger of generateDailySnapshot with injected time:
        await generator.generateDailySnapshot(
          orgId,
          operationalDay,
          closedAtUtc: injectedNow,
        );

        final snapshot = (await snapshotRepo.findAll(
          organizationId: orgId,
        )).first;

        expect(
          snapshot.closedAtUtc,
          equals(injectedNow),
          reason:
              'Stored closedAtUtc must match the injected audit timestamp exactly',
        );
        expect(snapshot.closedAtUtc.isUtc, isTrue);
      },
    );
  });
}
