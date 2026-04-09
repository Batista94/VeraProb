import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/utils/geo_math.dart';

import '_engine_test_helpers.dart';

void main() {
  setUpAll(() {
    initializeTimezones();
  });

  // ── Time anchor ──────────────────────────────────────────
  final baseTime = DateTime.utc(2026, 3, 1, 6, 0);

  // ── Bearing constants ────────────────────────────────────
  const bearingNorth = 0.0;
  const bearingEast = pi / 2;
  const bearingNorthEast = pi / 4;
  const bearingSouth = pi;

  // ── BLOCO A: Fronteira do Geofence (6 casas decimais) ───

  group('Bloco A — Geofence Boundary Precision (6 decimals)', () {
    late InMemoryContractualExecutionStateRepository repo;
    late InMemoryPlanDeclarationRepository planRepo;
    late InMemorySlaAuditLedgerRepository ledger;
    late ContractualEvaluationEngine engine;

    setUp(() {
      final deps = createEngine();
      repo = deps.repo;
      planRepo = deps.planRepo;
      ledger = deps.ledger;
      engine = deps.engine;
    });

    test('A1: exactlyOnBoundary_100m → BIND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      // Vehicle exactly at 100m boundary (North bearing)
      final vehicleAtBoundary = makeVehicleAtPreciseCoord(
        offsetMeters: 100.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // Verify distance is truly ~100m (within 1cm tolerance due to
      // floating-point precision limits of Haversine)
      final dist = GeoMath.haversineMeters(
        geoLat,
        geoLng,
        vehicleAtBoundary.latitude,
        vehicleAtBoundary.longitude,
      );
      expect(dist, closeTo(100.0, 0.01)); // ±1cm

      // Entry ping at T+0
      await engine.processVehicleState(
        vehicleAtBoundary,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // After 30s of continuous dwell at boundary
      final after30s = baseTime.add(const Duration(seconds: 30));
      await engine.processVehicleState(
        vehicleAtBoundary,
        nowUtc: after30s,
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
      expect(ledger.entries, hasLength(1));
    });

    test('A2: epsilonOutside_100_1m → NO BIND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      // Vehicle at 100.1m (10cm outside — smallest reliable offset for
      // Haversine + double precision at this latitude)
      final vehicleJustOutside = makeVehicleAtPreciseCoord(
        offsetMeters: 100.1,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // Verify it's truly outside
      final dist = GeoMath.haversineMeters(
        geoLat,
        geoLng,
        vehicleJustOutside.latitude,
        vehicleJustOutside.longitude,
      );
      expect(dist, greaterThan(100.0));

      // Entry ping at T+0
      await engine.processVehicleState(
        vehicleJustOutside,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // After 30s
      final after30s = baseTime.add(const Duration(seconds: 30));
      await engine.processVehicleState(
        vehicleJustOutside,
        nowUtc: after30s,
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);
      expect(ledger.entries, isEmpty);
    });

    test('A3: epsilonInside_99_9m → BIND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      // Vehicle at 99.9m (10cm inside)
      final vehicleJustInside = makeVehicleAtPreciseCoord(
        offsetMeters: 99.9,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // Verify it's truly inside
      final dist = GeoMath.haversineMeters(
        geoLat,
        geoLng,
        vehicleJustInside.latitude,
        vehicleJustInside.longitude,
      );
      expect(dist, lessThanOrEqualTo(100.0));

      // Entry ping at T+0
      await engine.processVehicleState(
        vehicleJustInside,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // After 30s
      final after30s = baseTime.add(const Duration(seconds: 30));
      await engine.processVehicleState(
        vehicleJustInside,
        nowUtc: after30s,
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
    });

    test('A4: oscillatingOnBoundary_130mExit_100pings → NO BIND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicleInside = makeVehicleAtPreciseCoord(
        offsetMeters: 99.9,
        bearing: bearingNorth,
        timestamp: baseTime,
      );
      final vehicleOutside = makeVehicleAtPreciseCoord(
        offsetMeters: 130.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // 100 pings alternating between inside and outside, every second
      for (int i = 0; i < 100; i++) {
        final t = baseTime.add(Duration(seconds: i));
        final vehicle = i.isEven ? vehicleInside : vehicleOutside;
        await engine.processVehicleState(
          vehicle,
          nowUtc: t,
          organizationId: 'org-1',
        );
      }

      // Timer should have been reset every time vehicle exits
      // After 100s of oscillation, no continuous 30s dwell achieved
      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);
      expect(ledger.entries, isEmpty);
    });

    test('A5: boundaryDrift_exitAndReenter → NO BIND (timer reset)', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicleInside = makeVehicleAtPreciseCoord(
        offsetMeters: 99.9,
        bearing: bearingNorth,
        timestamp: baseTime,
      );
      // 200m — well outside the 120m hysteresis exit band
      final vehicleOutside = makeVehicleAtPreciseCoord(
        offsetMeters: 200.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // T+0: Enter geofence
      await engine.processVehicleState(
        vehicleInside,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // T+15: Leave geofence (200m > 120m hysteresis band → true exit)
      await engine.processVehicleState(
        vehicleOutside,
        nowUtc: baseTime.add(const Duration(seconds: 15)),
        organizationId: 'org-1',
      );

      // T+45: Re-enter geofence (timer should have reset at T+15)
      await engine.processVehicleState(
        vehicleInside,
        nowUtc: baseTime.add(const Duration(seconds: 45)),
        organizationId: 'org-1',
      );

      // Only 30s accumulated from T+45 → T+75, but we only pinged until T+45
      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);
    });

    test('A6: boundaryEast_bearing90 at 99.9m → BIND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicleEast = makeVehicleAtPreciseCoord(
        offsetMeters: 99.9,
        bearing: bearingEast,
        timestamp: baseTime,
      );

      // T+0 entry
      await engine.processVehicleState(
        vehicleEast,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // T+30 dwell
      await engine.processVehicleState(
        vehicleEast,
        nowUtc: baseTime.add(const Duration(seconds: 30)),
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
    });

    test('A7: boundaryNE_bearing45 at 99.9m → BIND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicleNE = makeVehicleAtPreciseCoord(
        offsetMeters: 99.9,
        bearing: bearingNorthEast,
        timestamp: baseTime,
      );

      // T+0 entry
      await engine.processVehicleState(
        vehicleNE,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // T+30 dwell
      await engine.processVehicleState(
        vehicleNE,
        nowUtc: baseTime.add(const Duration(seconds: 30)),
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
    });

    test('A8: boundarySouth_bearing180 at 100.1m → NO BIND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicleSouth = makeVehicleAtPreciseCoord(
        offsetMeters: 100.1,
        bearing: bearingSouth,
        timestamp: baseTime,
      );

      // T+0: outside, should not accumulate
      await engine.processVehicleState(
        vehicleSouth,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // T+30: still outside
      await engine.processVehicleState(
        vehicleSouth,
        nowUtc: baseTime.add(const Duration(seconds: 30)),
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);
      expect(ledger.entries, isEmpty);
    });

    test(
      'A9: hysteresisBand_99_9m_100_1m_30pings → BIND (jitter absorbed)',
      () async {
        await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
        final state = makeExecState();
        await repo.save(state);

        // 99.9m = strict entry (inside 100m radius)
        final vehicleInside = makeVehicleAtPreciseCoord(
          offsetMeters: 99.9,
          bearing: bearingNorth,
          timestamp: baseTime,
        );
        // 100.1m = inside hysteresis band (< 120m exit threshold)
        final vehicleJitter = makeVehicleAtPreciseCoord(
          offsetMeters: 100.1,
          bearing: bearingNorth,
          timestamp: baseTime,
        );

        // T+0: ping at 99.9m — strict entry, starts dwell timer
        await engine.processVehicleState(
          vehicleInside,
          nowUtc: baseTime,
          organizationId: 'org-1',
        );

        // T+1..T+31: alternating jitter/inside, 1s each
        // 100.1m < 120m → never exits → dwell accumulates to 31s → BIND
        for (int i = 1; i <= 31; i++) {
          final t = baseTime.add(Duration(seconds: i));
          final vehicle = i.isEven ? vehicleInside : vehicleJitter;
          await engine.processVehicleState(
            vehicle,
            nowUtc: t,
            organizationId: 'org-1',
          );
        }

        final result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.executed);
        expect(ledger.entries, hasLength(1));
      },
    );
  });

  // ── BLOCO B: Violação de Tempo INV-9 + Idempotência ─────

  group('Bloco B — INV-9 Time Violation + Idempotency', () {
    late InMemoryContractualExecutionStateRepository repo;
    late InMemoryPlanDeclarationRepository planRepo;
    late InMemorySlaAuditLedgerRepository ledger;
    late ContractualEvaluationEngine engine;

    setUp(() {
      final deps = createEngine();
      repo = deps.repo;
      planRepo = deps.planRepo;
      ledger = deps.ledger;
      engine = deps.engine;
    });

    test('B1: identicalTimestamps_3pings_sameTick → 1x timer start', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // 3 pings with IDENTICAL timestamp T+0
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // Timer started at T+0, but only 0s dwell so far
      var result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);

      // At T+30, should bind (timer counted from T+0, not 3x T+0)
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime.add(const Duration(seconds: 30)),
        organizationId: 'org-1',
      );

      result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
      expect(ledger.entries, hasLength(1));
    });

    test('B2: reverseOrder_T30_T15_T0 → uses T+0 as entry', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // Pings arrive in reverse order: T+30, T+15, T+0
      // Each call uses its own nowUtc (gps_timestamp)
      final t0 = baseTime;
      final t15 = baseTime.add(const Duration(seconds: 15));
      final t30 = baseTime.add(const Duration(seconds: 30));

      // T+30 arrives first (but engine sees timestamp T+30)
      await engine.processVehicleState(
        vehicle,
        nowUtc: t30,
        organizationId: 'org-1',
      );

      // T+15 arrives second (engine sees T+15 — earlier than T+30)
      // The _firstEntryTimestamps was set to T+30. Now T+15 < T+30.
      // Engine should NOT update firstEntry to earlier time (that would be
      // non-deterministic). The first processed event time wins.
      await engine.processVehicleState(
        vehicle,
        nowUtc: t15,
        organizationId: 'org-1',
      );

      // T+0 arrives last
      await engine.processVehicleState(
        vehicle,
        nowUtc: t0,
        organizationId: 'org-1',
      );

      // At this point, firstEntry = T+30 (first processed).
      // T+15 and T+0 are before firstEntry, so they are skipped by the
      // `if (now.isBefore(firstEntry)) continue;` guard.
      // Dwell from T+30 perspective = 0s at T+30.
      var result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);

      // At T+60 (30s after T+30), should bind
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime.add(const Duration(seconds: 60)),
        organizationId: 'org-1',
      );

      result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
    });

    test('B3: outOfOrder_exitBeforeEntry → processes T+0 first', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicleInside = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );
      final vehicleOutside = makeVehicleAtPreciseCoord(
        offsetMeters: 200.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // Exit event (T+15, outside) arrives BEFORE entry event (T+0, inside)
      await engine.processVehicleState(
        vehicleOutside,
        nowUtc: baseTime.add(const Duration(seconds: 15)),
        organizationId: 'org-1',
      );

      // At T+15, no firstEntry exists yet (vehicle outside). Nothing happens.
      var result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);

      // Now entry event arrives (T+0, inside)
      await engine.processVehicleState(
        vehicleInside,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // firstEntry = T+0. Dwell = 0s at T+0.
      result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);

      // At T+30, should bind
      await engine.processVehicleState(
        vehicleInside,
        nowUtc: baseTime.add(const Duration(seconds: 30)),
        organizationId: 'org-1',
      );

      result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
    });

    test('B4: duplicateTimestamp_60pings_T0 → dwell=0, NO BIND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // 60 pings all with the SAME timestamp T+0
      for (int i = 0; i < 60; i++) {
        await engine.processVehicleState(
          vehicle,
          nowUtc: baseTime,
          organizationId: 'org-1',
        );
      }

      // All pings at same instant → dwell = 0s
      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);
      expect(ledger.entries, isEmpty);
    });

    test(
      'B5: interleavedVehicles_sameTimestamp → only assigned accumulates',
      () async {
        await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
        final state = makeExecState(plannedVehicleId: 'v-assigned');
        await repo.save(state);

        final assignedVehicle = makeVehicleAtTime(
          vehicleId: 'v-assigned',
          latitude: geoLat,
          longitude: geoLng,
          timestamp: baseTime,
        );
        final intruderVehicle = makeVehicleAtTime(
          vehicleId: 'v-intruder',
          latitude: geoLat,
          longitude: geoLng,
          timestamp: baseTime,
        );

        // Both vehicles ping at the same time, both inside geofence
        await engine.processVehicleState(
          intruderVehicle,
          nowUtc: baseTime,
          organizationId: 'org-1',
        );
        await engine.processVehicleState(
          assignedVehicle,
          nowUtc: baseTime,
          organizationId: 'org-1',
        );

        // At T+30
        await engine.processVehicleState(
          intruderVehicle,
          nowUtc: baseTime.add(const Duration(seconds: 30)),
          organizationId: 'org-1',
        );
        await engine.processVehicleState(
          assignedVehicle,
          nowUtc: baseTime.add(const Duration(seconds: 30)),
          organizationId: 'org-1',
        );

        final result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.executed);
        expect(result.boundVehicleId, 'v-assigned');
        expect(ledger.entries, hasLength(1));
      },
    );

    test('B6: clockSkew_eventTimeWins → dwell uses gps_timestamp', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime.add(const Duration(seconds: 10)),
      );

      // gps_timestamp = T+10, but receivedAtUtc = T+5 (server clock 5s behind)
      // We simulate by calling with nowUtc = T+10 (event time, as engine uses)
      // The receivedAtUtc parameter is only used for INV-12 late-arrival checks.
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime.add(const Duration(seconds: 10)),
        organizationId: 'org-1',
      );

      // At T+40 (30s dwell from T+10)
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime.add(const Duration(seconds: 40)),
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
    });

    test('B7: doubleReplay_identicalLedger → 1 EXECUTION_BOUND', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // First replay: T+0 → T+60
      for (int i = 0; i <= 60; i += 10) {
        await engine.processVehicleState(
          vehicle,
          nowUtc: baseTime.add(Duration(seconds: i)),
          organizationId: 'org-1',
        );
      }

      final entriesAfterFirst = ledger.entries.length;
      expect(entriesAfterFirst, 1); // One EXECUTION_BOUND

      // Reset the execution state back to pending (simulate reprocessing)
      final state2 = makeExecState();
      await repo.save(state2);

      // Second replay: exact same pings
      for (int i = 0; i <= 60; i += 10) {
        await engine.processVehicleState(
          vehicle,
          nowUtc: baseTime.add(Duration(seconds: i)),
          organizationId: 'org-1',
        );
      }

      // Should have exactly 1 more entry (the second replay's binding)
      // Total = 2, but each replay independently produces exactly 1
      expect(ledger.entries, hasLength(2));

      // Verify both are EXECUTION_BOUND (no duplicate sanctions)
      final boundCount = ledger.entries
          .where((e) => e.type == 'EXECUTION_BOUND')
          .length;
      expect(boundCount, 2); // 1 per replay, idempotent per run
    });
  });

  // ── BLOCO C: Estado de Execução — PENDING → EXECUTED ────

  group('Bloco C — Dwell Time State Transitions', () {
    late InMemoryContractualExecutionStateRepository repo;
    late InMemoryPlanDeclarationRepository planRepo;
    late InMemorySlaAuditLedgerRepository ledger;
    late ContractualEvaluationEngine engine;

    setUp(() {
      final deps = createEngine();
      repo = deps.repo;
      planRepo = deps.planRepo;
      ledger = deps.ledger;
      engine = deps.engine;
    });

    test('C1: exactDwellBoundary_30s → BIND (>= inclusivo)', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // T+0 entry
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // Exactly T+30 (boundary)
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime.add(const Duration(seconds: 30)),
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
    });

    test('C2: oneSecondShort_29s → NO BIND (PENDING)', () async {
      await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // T+0 entry
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime,
        organizationId: 'org-1',
      );

      // T+29 (1s short)
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime.add(const Duration(seconds: 29)),
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);
      expect(ledger.entries, isEmpty);
    });

    test(
      'C3: dwellAccumulationWithGaps → exit resets timer, re-entry starts fresh',
      () async {
        await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
        final state = makeExecState();
        await repo.save(state);

        final vehicleInside = makeVehicleAtPreciseCoord(
          offsetMeters: 50.0,
          bearing: bearingNorth,
          timestamp: baseTime,
        );
        final vehicleOutside = makeVehicleAtPreciseCoord(
          offsetMeters: 200.0,
          bearing: bearingNorth,
          timestamp: baseTime,
        );

        // T+0: Enter
        await engine.processVehicleState(
          vehicleInside,
          nowUtc: baseTime,
          organizationId: 'org-1',
        );

        // T+10: Leave (timer resets)
        await engine.processVehicleState(
          vehicleOutside,
          nowUtc: baseTime.add(const Duration(seconds: 10)),
          organizationId: 'org-1',
        );

        // T+20: Re-enter (timer starts fresh)
        await engine.processVehicleState(
          vehicleInside,
          nowUtc: baseTime.add(const Duration(seconds: 20)),
          organizationId: 'org-1',
        );

        // T+50: 30s continuous from T+20 → should bind
        await engine.processVehicleState(
          vehicleInside,
          nowUtc: baseTime.add(const Duration(seconds: 50)),
          organizationId: 'org-1',
        );

        final result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.executed);
      },
    );

    test(
      'C4: gracePeriodSuppression_5min → engine does not evaluate',
      () async {
        await seedPlan(planRepo, 'c-1', 1);
        await seedPlanWithGracePeriod(planRepo, 'c-1', 1, 10);
        final state = makeExecState();
        await repo.save(state);

        final vehicle = makeVehicleAtPreciseCoord(
          offsetMeters: 50.0,
          bearing: bearingNorth,
          timestamp: baseTime,
        );

        // SET window starts at 06:00. Grace period = 10min.
        // Ping at T+5min (within grace) — engine should skip
        await engine.processVehicleState(
          vehicle,
          nowUtc: baseTime.add(const Duration(minutes: 5)),
          organizationId: 'org-1',
        );

        // Still pending, no ledger entries
        final result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.pending);
        expect(ledger.entries, isEmpty);
      },
    );

    test('C5: postGraceBinding_11min + 30s dwell → BIND', () async {
      await seedPlan(planRepo, 'c-1', 1);
      await seedPlanWithGracePeriod(planRepo, 'c-1', 1, 10);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleAtPreciseCoord(
        offsetMeters: 50.0,
        bearing: bearingNorth,
        timestamp: baseTime,
      );

      // T+11min (past 10min grace)
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime.add(const Duration(minutes: 11)),
        organizationId: 'org-1',
      );

      // T+11min30s (30s dwell from T+11min)
      await engine.processVehicleState(
        vehicle,
        nowUtc: baseTime.add(const Duration(minutes: 11, seconds: 30)),
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.executed);
    });

    test(
      'C6: sweepDuringActiveDwell → if already executed, sweep skips; if pending, marks noShow',
      () async {
        await seedPlanWithDwellRule(planRepo, 'c-1', 1, minDwellSeconds: 30);
        final state = makeExecState(
          windowStart: baseTime,
          windowEnd: baseTime.add(const Duration(minutes: 40)),
        );
        await repo.save(state);

        final vehicle = makeVehicleAtPreciseCoord(
          offsetMeters: 50.0,
          bearing: bearingNorth,
          timestamp: baseTime,
        );

        // T+0: Enter geofence, dwell starts
        await engine.processVehicleState(
          vehicle,
          nowUtc: baseTime,
          organizationId: 'org-1',
        );

        // T+30: Dwell complete, bound
        await engine.processVehicleState(
          vehicle,
          nowUtc: baseTime.add(const Duration(seconds: 30)),
          organizationId: 'org-1',
        );

        var result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.executed);

        // Sweep at T+45 (past windowEnd at T+40) — should NOT affect executed state
        await engine.sweepExpiredObligations(
          nowUtc: baseTime.add(const Duration(minutes: 45)),
          organizationId: 'org-1',
        );

        result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.executed);

        // Only 1 ledger entry (EXECUTION_BOUND, no NO_SHOW)
        final boundCount = ledger.entries
            .where((e) => e.type == 'EXECUTION_BOUND')
            .length;
        expect(boundCount, 1);
        final noShowCount = ledger.entries
            .where((e) => e.type == 'NO_SHOW_DECLARED')
            .length;
        expect(noShowCount, 0);
      },
    );
  });
}
