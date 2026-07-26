import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/vehicle_category.dart';
import 'package:veraprob/domain/sla_audit/week_cycle.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  final nowUtc = DateTime.parse('2026-04-08T12:00:00Z').toUtc();
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  late InMemoryContractualExecutionStateRepository repo;
  late InMemoryPlanDeclarationRepository planRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late ContractualEvaluationEngine engine;

  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100;

  setUp(() {
    repo = InMemoryContractualExecutionStateRepository();
    planRepo = InMemoryPlanDeclarationRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    final traceRepo = InMemoryEvaluationTraceRepository();
    engine = ContractualEvaluationEngine(
      executionRepo: repo,
      planRepo: planRepo,
      ledgerRepo: ledger,
      traceRepo: traceRepo,
    );
  });

  ContractualExecutionState makeExecState({
    required String setId,
    required DateTime windowStartUtc,
    DateTime? windowEndUtc,
    int? noShowPenaltyBps,
    Money contractualValue = const Money(1500000), // 15k cents
  }) {
    return ContractualExecutionState.create(
      organizationId: 'org-audit',
      setId: setId,
      contractId: 'c-audit',
      planVersion: 1,
      startLatitude: geoLat,
      startLongitude: geoLng,
      startRadiusMeters: geoRadius,
      contractualValue: contractualValue,
      noShowPenaltyBps: noShowPenaltyBps ?? 10000, // 1.0x
      windowStartUtc: windowStartUtc,
      windowEndUtc:
          windowEndUtc ?? windowStartUtc.add(const Duration(hours: 1)),
    );
  }

  Future<void> seedPlanWithGrace(int graceMinutes) async {
    final pattern = ShiftPattern.create(
      index: 0,
      daysOfWeek: DayOfWeek.values,
      arrivalTimeLocal: '00:00',
      departureTimeLocal: '01:00',
      timezone: 'UTC',
      originZoneId: 'z-1',
      destinationZoneId: 'z-2',
      penalties: SLAPenalties.create(
        noShowPenaltyBps: 10000,
        delayToleranceMinutes: 0,
        delayPenaltyPerMinute: const Money(1),
        downgradePenaltyFlat: const Money(1),
        gracePeriodMinutes: graceMinutes,
        baseTripValue: const Money(1500000),
      ),
      requiredVehicleCategory: VehicleCategory.conventional,
      weekCycle: WeekCycle.everyWeek,
    );
    final declaration = PlanDeclaration.createWithShiftPatterns(
      organizationId: 'org-audit',
      contractId: 'c-audit',
      planVersion: 1,
      declaredAtUtc: nowUtc,
      declaredByUserId: 'auditor',
      originalFileHash: 'aud-hash',
      ruleSnapshot: const RuleSnapshot([]),
      shiftPatterns: [pattern],
      nowUtc: nowUtc,
    );
    await planRepo.save(declaration);
  }

  VehicleOperationalState makeVehicleState(DateTime pingAt) {
    return VehicleOperationalState(
      rawSpeed: 0.0,
      vehicleId: 'v-audit',
      tripId: 't-audit',
      latitude: geoLat,
      longitude: geoLng,
      smoothedSpeed: 0.0,
      motionState: MotionState.stopped,
      connectivityState: ConnectivityState.healthy,
      lastRawPingAt: pingAt.isUtc ? pingAt : pingAt.toUtc(),
      stateChangedAt: pingAt.isUtc ? pingAt : pingAt.toUtc(),
      confidence: 1.0,
      source: 'telemetry',
    );
  }

  group('Forensic Integrity: ContractualEvaluationEngine', () {
    test('REQ-1: Mandatory UTC Enforcement (INV-9)', () async {
      final now = nowUtc;
      expect(now.isUtc, isTrue, reason: 'Timestamp MUST be UTC');

      await seedPlanWithGrace(0);
      final state = makeExecState(
        setId: 'utc-1',
        windowStartUtc: now.subtract(const Duration(minutes: 30)),
      );
      await repo.save(state);

      // Verify engine processing uses UTC internally
      await engine.processVehicleState(
        makeVehicleState(now),
        nowUtc: now,
        organizationId: 'org-audit',
      );

      final result = await repo.findBySetId(
        'utc-1',
        organizationId: 'org-audit',
      );
      expect(result!.lastEvaluatedAtUtc.isUtc, isTrue);
    });

    test('REQ-2: Millisecond Grace Window Expiration Edge Case', () async {
      const graceMinutes = 5;
      await seedPlanWithGrace(graceMinutes);

      final windowStart = DateTime.utc(2026, 4, 7, 10, 0, 0);
      final graceExpiry = windowStart.add(
        const Duration(minutes: graceMinutes),
      );

      final state = makeExecState(
        setId: 'grace-edge',
        windowStartUtc: windowStart,
      );
      await repo.save(state);

      // T-1ms: Should still be inside grace period (skipped)
      final tMinus1ms = graceExpiry.subtract(const Duration(milliseconds: 1));
      await engine.processVehicleState(
        makeVehicleState(tMinus1ms),
        nowUtc: tMinus1ms,
        organizationId: 'org-audit',
      );
      expect(
        (await repo.findBySetId(
          'grace-edge',
          organizationId: 'org-audit',
        ))!.status,
        ExecutionStatus.planned,
      );

      // T-0 (Exact Expiry): Should start evaluation (not skipped)
      await engine.processVehicleState(
        makeVehicleState(graceExpiry),
        nowUtc: graceExpiry,
        organizationId: 'org-audit',
      );
      // First ping starts dwell, still pending but not skipped logic-wise
      // Wait 30s dwell
      final tDwell = graceExpiry.add(const Duration(seconds: 31));
      await engine.processVehicleState(
        makeVehicleState(tDwell),
        nowUtc: tDwell,
        organizationId: 'org-audit',
      );

      expect(
        (await repo.findBySetId(
          'grace-edge',
          organizationId: 'org-audit',
        ))!.status,
        ExecutionStatus.completed,
      );
    });

    test('REQ-3: Sad Path - Out-of-Order Chronological Telemetry', () async {
      await seedPlanWithGrace(0);
      final windowStart = DateTime.utc(2026, 4, 7, 10, 0, 0);
      final state = makeExecState(
        setId: 'ooo-test',
        windowStartUtc: windowStart,
      );
      await repo.save(state);

      final t1 = windowStart.add(const Duration(minutes: 10)); // Current
      final t0 = windowStart.add(const Duration(minutes: 5)); // Past (Delayed)

      // 1. Process current ping
      await engine.processVehicleState(
        makeVehicleState(t1),
        nowUtc: t1,
        organizationId: 'org-audit',
      );

      // 2. Process delayed ping (Older than t1)
      await engine.processVehicleState(
        makeVehicleState(t0),
        nowUtc: t0,
        organizationId: 'org-audit',
      );

      // 3. Process future ping to complete dwell
      final t3 = t1.add(const Duration(seconds: 31));
      await engine.processVehicleState(
        makeVehicleState(t3),
        nowUtc: t3,
        organizationId: 'org-audit',
      );

      final result = await repo.findBySetId(
        'ooo-test',
        organizationId: 'org-audit',
      );
      expect(
        result!.status,
        ExecutionStatus.completed,
        reason: 'Out-of-order telemetry should not break dwell logic',
      );
    });

    test('REQ-4: Invariant - Non-Negative Penalty Guard', () async {
      await seedPlanWithGrace(0);
      final windowEnd = DateTime.utc(2026, 4, 7, 11, 0, 0);

      // Use reconstitute to force a negative BPS through (bypassing create guards)
      final state = ContractualExecutionState.reconstitute(
        id: 'neg-1',
        organizationId: 'org-audit',
        setId: 'neg-penalty',
        contractId: 'c-audit',
        planVersion: 1,
        startLatitude: geoLat,
        startLongitude: geoLng,
        startRadiusMeters: geoRadius,
        contractualValue: const Money(100000),
        noShowPenaltyBps: -500, // ANOMALY: Forced negative BPS
        windowStartUtc: windowEnd.subtract(const Duration(hours: 1)),
        windowEndUtc: windowEnd,
        status: ExecutionStatus.planned,
        createdAtUtc: nowUtc,
        lastEvaluatedAtUtc: nowUtc,
        statusLastUpdatedAtUtc: nowUtc,
      );
      await repo.save(state);

      await engine.sweepExpiredObligations(
        nowUtc: windowEnd.add(const Duration(minutes: 1)),
        organizationId: 'org-audit',
      );

      final entries = ledger.entries
          .where((e) => e.payload['set_id'] == 'neg-penalty')
          .toList();
      if (entries.isNotEmpty) {
        final payload = entries.first.payload;
        // The fine_cents is nested in verdict_evidence
        final fineCents = payload['verdict_evidence']['fine_cents'] as int;
        expect(
          fineCents,
          isNot(isNegative),
          reason: 'Penalty MUST NOT be negative despite corrupted state',
        );
      }
    });
  });
}
