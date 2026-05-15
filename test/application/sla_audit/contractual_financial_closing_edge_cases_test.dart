// ignore_for_file: lines_longer_than_80_chars, prefer_const_declarations
// =============================================================================
// test/application/sla_audit/contractual_financial_closing_edge_cases_test.dart
//
// Edge case coverage for ContractualFinancialSnapshotGenerator:
// - Revenue Protection (executed/inhibited states)
// - BPS 100% (10000 units)
// - BPS Overflow Safety (500% BPS)
// - Zero State Persistence
// - Cross-tenant Guard (INV-1)
//
// Invariants enforced:
// - INV-1: Tenant isolation (organization_id filtering)
// - INV-4: Money Type (BIGINT cents)
// - INV-5: BPS Precision (symmetric rounding)
// =============================================================================

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state_repository.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_financial_snapshot_repository.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/sla_audit_ledger_repository.dart';

// ── Stubs ─────────────────────────────────────────────────────────────────────

class _FakeExecutionRepo implements ContractualExecutionStateRepository {
  final List<ContractualExecutionState> _states = [];

  void addState(ContractualExecutionState state) => _states.add(state);

  @override
  Future<List<ContractualExecutionState>> findAll({
    required String organizationId,
  }) async => _states.where((s) => s.organizationId == organizationId).toList();

  @override
  Future<List<ContractualExecutionState>> findByContract(
    String contractId, {
    required String organizationId,
  }) async => _states
      .where(
        (s) => s.organizationId == organizationId && s.contractId == contractId,
      )
      .toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSnapshotRepo implements ContractualFinancialSnapshotRepository {
  final List<ContractualFinancialDailySnapshot> _snapshots = [];

  @override
  Future<bool> existsForDate(
    String organizationId,
    DateTime operationalDateUtc, {
    String? contractId,
  }) async => _snapshots.any(
    (s) =>
        s.organizationId == organizationId &&
        s.operationalDateUtc == operationalDateUtc &&
        (contractId == null || s.contractId == contractId),
  );

  @override
  Future<void> save(ContractualFinancialDailySnapshot snapshot) async {
    _snapshots.add(snapshot);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLedgerRepo implements SlaAuditLedgerRepository {
  @override
  Future<String?> getLastEntryId({
    String? organizationId,
    String? contractId,
  }) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClock implements IDateTimeProvider {
  final DateTime _now;
  _FakeClock(this._now);

  @override
  DateTime nowUtc() => _now;

  @override
  DateTime nowBrazil() => _now;
}

// ── Factories ─────────────────────────────────────────────────────────────────

ContractualExecutionState makeState({
  required String organizationId,
  required String contractId,
  required ExecutionStatus status,
  required Money value,
  required int noShowPenaltyBps,
  required DateTime windowStartUtc,
}) {
  final state = ContractualExecutionState.create(
    organizationId: organizationId,
    setId: 'set-1',
    contractId: contractId,
    planVersion: 1,
    startLatitude: -23.5612,
    startLongitude: -46.6560,
    startRadiusMeters: 50,
    contractualValue: value,
    noShowPenaltyBps: noShowPenaltyBps,
    windowStartUtc: windowStartUtc,
    windowEndUtc: windowStartUtc.add(const Duration(hours: 1)),
  );

  if (status == ExecutionStatus.completed) {
    state.bindExecution(
      vehicleId: 'vehicle-1',
      latitude: -23.5612,
      longitude: -46.6560,
      timestampUtc: windowStartUtc.add(const Duration(minutes: 30)),
    );
  } else if (status == ExecutionStatus.failed) {
    state.markFailed(windowStartUtc.add(const Duration(hours: 2)));
  }

  return state;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  final kEpoch = DateTime.utc(2026, 4, 14, 12, 0, 0);

  group('Revenue Protection', () {
    // C1 — Executed state → lostRevenue == 0
    test('C1: Executed state -> lostRevenue == 0', () async {
      final executionRepo = _FakeExecutionRepo();
      final snapshotRepo = _FakeSnapshotRepo();
      final ledgerRepo = _FakeLedgerRepo();
      final clock = _FakeClock(kEpoch);

      executionRepo.addState(
        makeState(
          organizationId: 'org-1',
          contractId: 'contract-1',
          status: ExecutionStatus.completed,
          value: const Money(10000),
          noShowPenaltyBps: 15000,
          windowStartUtc: kEpoch,
        ),
      );

      final generator = ContractualFinancialSnapshotGenerator(
        executionRepo: executionRepo,
        snapshotRepo: snapshotRepo,
        ledgerRepo: ledgerRepo,
        clock: clock,
        engineVersion: 'veraprob-core_v4-test',
      );

      await generator.generateDailySnapshot('org-1', kEpoch);

      expect(snapshotRepo._snapshots, hasLength(1));
      expect(snapshotRepo._snapshots.first.lostRevenue.cents, 0);
    });

    // C2 — Inhibited state → lostRevenue == 0
    test('C2: Inhibited state -> lostRevenue == 0', () async {
      final executionRepo = _FakeExecutionRepo();
      final snapshotRepo = _FakeSnapshotRepo();
      final ledgerRepo = _FakeLedgerRepo();
      final clock = _FakeClock(kEpoch);

      final state = makeState(
        organizationId: 'org-1',
        contractId: 'contract-1',
        status: ExecutionStatus.planned,
        value: const Money(10000),
        noShowPenaltyBps: 15000,
        windowStartUtc: kEpoch,
      );

      executionRepo.addState(state);

      final generator = ContractualFinancialSnapshotGenerator(
        executionRepo: executionRepo,
        snapshotRepo: snapshotRepo,
        ledgerRepo: ledgerRepo,
        clock: clock,
        engineVersion: 'veraprob-core_v4-test',
      );

      await generator.generateDailySnapshot('org-1', kEpoch);

      expect(snapshotRepo._snapshots, hasLength(1));
      expect(snapshotRepo._snapshots.first.lostRevenue.cents, 0);
    });

    // C3 — NoShow state → lostRevenue > 0
    test('C3: NoShow state -> lostRevenue > 0', () async {
      final executionRepo = _FakeExecutionRepo();
      final snapshotRepo = _FakeSnapshotRepo();
      final ledgerRepo = _FakeLedgerRepo();
      final clock = _FakeClock(kEpoch);

      executionRepo.addState(
        makeState(
          organizationId: 'org-1',
          contractId: 'contract-1',
          status: ExecutionStatus.failed,
          value: const Money(10000),
          noShowPenaltyBps: 15000,
          windowStartUtc: kEpoch,
        ),
      );

      final generator = ContractualFinancialSnapshotGenerator(
        executionRepo: executionRepo,
        snapshotRepo: snapshotRepo,
        ledgerRepo: ledgerRepo,
        clock: clock,
        engineVersion: 'veraprob-core_v4-test',
      );

      await generator.generateDailySnapshot('org-1', kEpoch);

      expect(snapshotRepo._snapshots, hasLength(1));
      expect(snapshotRepo._snapshots.first.lostRevenue.cents, greaterThan(0));
    });
  });

  group('BPS Safety', () {
    // C4 — BPS 100% (10000 units) → cents == lostRevenue
    test('C4: BPS 100% (10000 units) -> cents == lostRevenue', () async {
      final executionRepo = _FakeExecutionRepo();
      final snapshotRepo = _FakeSnapshotRepo();
      final ledgerRepo = _FakeLedgerRepo();
      final clock = _FakeClock(kEpoch);

      executionRepo.addState(
        makeState(
          organizationId: 'org-1',
          contractId: 'contract-1',
          status: ExecutionStatus.failed,
          value: const Money(10000),
          noShowPenaltyBps: 10000,
          windowStartUtc: kEpoch,
        ),
      );

      final generator = ContractualFinancialSnapshotGenerator(
        executionRepo: executionRepo,
        snapshotRepo: snapshotRepo,
        ledgerRepo: ledgerRepo,
        clock: clock,
        engineVersion: 'veraprob-core_v4-test',
      );

      await generator.generateDailySnapshot('org-1', kEpoch);

      expect(snapshotRepo._snapshots.first.lostRevenue.cents, 10000);
    });

    // C5 — BPS Overflow Safety → BigInt prevents truncation
    test('C5: BPS Overflow Safety -> 500% BPS on 200 cents uses BigInt', () {
      final value = const Money(200);
      final result = value.multiplyByBps(50000);
      expect(result.cents, 1000);
    });

    // C6 — Zero State Persistence → snapshot persisted even with totalObligations == 0
    test(
      'C6: Zero State Persistence -> snapshot persisted with totalObligations == 0',
      () async {
        final executionRepo = _FakeExecutionRepo();
        final snapshotRepo = _FakeSnapshotRepo();
        final ledgerRepo = _FakeLedgerRepo();
        final clock = _FakeClock(kEpoch);

        final generator = ContractualFinancialSnapshotGenerator(
          executionRepo: executionRepo,
          snapshotRepo: snapshotRepo,
          ledgerRepo: ledgerRepo,
          clock: clock,
          engineVersion: 'veraprob-core_v4-test',
        );

        await generator.generateDailySnapshot('org-1', kEpoch);

        expect(snapshotRepo._snapshots, hasLength(1));
        expect(snapshotRepo._snapshots.first.totalObligations, 0);
      },
    );

    // C7 — Cross-tenant Guard → snapshot NOT persisted if tenant diverges
    test(
      'C7: Cross-tenant Guard -> snapshot NOT persisted if tenant diverges',
      () async {
        final executionRepo = _FakeExecutionRepo();
        final snapshotRepo = _FakeSnapshotRepo();
        final ledgerRepo = _FakeLedgerRepo();
        final clock = _FakeClock(kEpoch);

        executionRepo.addState(
          makeState(
            organizationId: 'org-2',
            contractId: 'contract-1',
            status: ExecutionStatus.completed,
            value: const Money(10000),
            noShowPenaltyBps: 15000,
            windowStartUtc: kEpoch,
          ),
        );

        final generator = ContractualFinancialSnapshotGenerator(
          executionRepo: executionRepo,
          snapshotRepo: snapshotRepo,
          ledgerRepo: ledgerRepo,
          clock: clock,
          engineVersion: 'veraprob-core_v4-test',
        );

        await generator.generateDailySnapshot(
          'org-1',
          kEpoch,
          contractId: 'contract-1',
        );

        expect(snapshotRepo._snapshots, isEmpty);
      },
    );
  });
}
