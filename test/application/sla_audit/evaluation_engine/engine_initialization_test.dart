import 'package:flutter_test/flutter_test.dart';

import '_engine_test_helpers.dart';

void main() {
  setUpAll(() {
    initializeTimezones();
  });

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

  group('ContractualEvaluationEngine — Initialization & Binding', () {
    test('binding occurs after 30s continuous dwell inside geofence', () async {
      await seedPlan(planRepo, 'c-1', 1);
      final state = makeExecState();
      await repo.save(state);

      final vehicle = makeVehicleState();
      final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
      final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);

      // First ping — enters geofence, timer starts
      await engine.processVehicleState(
        vehicle,
        nowUtc: t0,
        organizationId: 'org-1',
      );
      final afterFirst = await repo.findBySetId('set-1');
      expect(afterFirst!.status, ExecutionStatus.pending);

      // Second ping — 31s later, still inside → binding
      await engine.processVehicleState(
        vehicle,
        nowUtc: t31,
        organizationId: 'org-1',
      );
      final afterBinding = await repo.findBySetId('set-1');
      expect(afterBinding!.status, ExecutionStatus.executed);
      expect(afterBinding.boundVehicleId, 'v-1');
      expect(ledger.entries, hasLength(1));
    });

    test('no binding if vehicle leaves geofence before 30s', () async {
      await seedPlan(planRepo, 'c-1', 1);
      final state = makeExecState();
      await repo.save(state);

      final insideVehicle = makeVehicleState();
      // ~500m away — well outside 100m radius
      final outsideVehicle = makeVehicleState(latitude: geoLat + 0.005);

      final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
      final t15 = DateTime.utc(2026, 3, 1, 6, 30, 15);
      final t45 = DateTime.utc(2026, 3, 1, 6, 30, 45);

      // Enter geofence
      await engine.processVehicleState(
        insideVehicle,
        nowUtc: t0,
        organizationId: 'org-1',
      );
      // Leave geofence at 15s
      await engine.processVehicleState(
        outsideVehicle,
        nowUtc: t15,
        organizationId: 'org-1',
      );
      // Re-enter at 45s — timer should have reset
      await engine.processVehicleState(
        insideVehicle,
        nowUtc: t45,
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);
      expect(ledger.entries, isEmpty);
    });

    test('plannedVehicleId is respected — wrong vehicle ignored', () async {
      await seedPlan(planRepo, 'c-1', 1);
      final state = makeExecState(plannedVehicleId: 'v-assigned');
      await repo.save(state);

      // Wrong vehicle inside geofence
      final wrongVehicle = makeVehicleState(vehicleId: 'v-intruder');
      final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
      final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);

      await engine.processVehicleState(
        wrongVehicle,
        nowUtc: t0,
        organizationId: 'org-1',
      );
      await engine.processVehicleState(
        wrongVehicle,
        nowUtc: t31,
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);

      // Correct vehicle binds normally
      final rightVehicle = makeVehicleState(vehicleId: 'v-assigned');
      await engine.processVehicleState(
        rightVehicle,
        nowUtc: t0,
        organizationId: 'org-1',
      );
      await engine.processVehicleState(
        rightVehicle,
        nowUtc: t31,
        organizationId: 'org-1',
      );

      final bound = await repo.findBySetId('set-1');
      expect(bound!.status, ExecutionStatus.executed);
      expect(bound.boundVehicleId, 'v-assigned');
    });

    test('sweepExpiredObligations marks NoShow correctly', () async {
      await seedPlan(planRepo, 'c-1', 1);
      final state = makeExecState(windowEnd: DateTime.utc(2026, 3, 1, 7, 0));
      await repo.save(state);

      final afterExpiry = DateTime.utc(2026, 3, 1, 7, 1);
      await engine.sweepExpiredObligations(
        nowUtc: afterExpiry,
        organizationId: 'org-1',
      );

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.noShow);
      expect(ledger.entries, hasLength(1));
    });

    test('finalized states are not reprocessed', () async {
      await seedPlan(planRepo, 'c-1', 1);
      final state = makeExecState();
      await repo.save(state);

      // Bind successfully
      final vehicle = makeVehicleState();
      final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
      final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);
      await engine.processVehicleState(
        vehicle,
        nowUtc: t0,
        organizationId: 'org-1',
      );
      await engine.processVehicleState(
        vehicle,
        nowUtc: t31,
        organizationId: 'org-1',
      );

      expect(ledger.entries, hasLength(1));

      // Process again — should NOT create another binding
      final t60 = DateTime.utc(2026, 3, 1, 6, 31, 0);
      final t91 = DateTime.utc(2026, 3, 1, 6, 31, 31);
      await engine.processVehicleState(
        vehicle,
        nowUtc: t60,
        organizationId: 'org-1',
      );
      await engine.processVehicleState(
        vehicle,
        nowUtc: t91,
        organizationId: 'org-1',
      );

      // Still only 1 event
      expect(ledger.entries, hasLength(1));
    });

    test('multiple execution states do not interfere', () async {
      await seedPlan(planRepo, 'c-1', 1);
      await seedPlan(planRepo, 'c-2', 1);

      final state1 = makeExecState(setId: 'set-1');
      final state2 = makeExecState(
        setId: 'set-2',
        // Geofence far away — vehicle won't match
        contractId: 'c-2',
      );
      await repo.save(state1);
      await repo.save(state2);

      final vehicle = makeVehicleState(); // at geoLat/geoLng
      final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
      final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);

      await engine.processVehicleState(
        vehicle,
        nowUtc: t0,
        organizationId: 'org-1',
      );
      await engine.processVehicleState(
        vehicle,
        nowUtc: t31,
        organizationId: 'org-1',
      );

      // state1 bound (vehicle is at geofence center)
      final r1 = await repo.findBySetId('set-1');
      expect(r1!.status, ExecutionStatus.executed);

      // state2 also bound (same geofence defaults)
      final r2 = await repo.findBySetId('set-2');
      expect(r2!.status, ExecutionStatus.executed);

      // Sweep should not affect finalized states
      await engine.sweepExpiredObligations(
        nowUtc: DateTime.utc(2026, 3, 1, 7, 1),
        organizationId: 'org-1',
      );
      expect(r1.status, ExecutionStatus.executed);
      expect(r2.status, ExecutionStatus.executed);
    });

    test(
      'idempotency: same payload twice does not duplicate processing',
      () async {
        await seedPlan(planRepo, 'c-1', 1);
        final state = makeExecState();
        await repo.save(state);
        final vehicle = makeVehicleState();

        final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
        final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);

        await engine.processVehicleState(
          vehicle,
          nowUtc: t0,
          organizationId: 'org-1',
        );
        await engine.processVehicleState(
          vehicle,
          nowUtc: t0,
          organizationId: 'org-1',
        ); // Duplicate

        await engine.processVehicleState(
          vehicle,
          nowUtc: t31,
          organizationId: 'org-1',
        );
        await engine.processVehicleState(
          vehicle,
          nowUtc: t31,
          organizationId: 'org-1',
        ); // Duplicate

        final result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.executed);
        expect(ledger.entries, hasLength(1));
      },
    );

    test(
      'out-of-order telemetry: older timestamp does not break dwell if already started',
      () async {
        await seedPlan(planRepo, 'c-1', 1);
        final state = makeExecState();
        await repo.save(state);
        final vehicleInside = makeVehicleState();
        final vehicleOutside = makeVehicleState(latitude: geoLat + 0.005);

        final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
        final tMinus10 = DateTime.utc(
          2026,
          3,
          1,
          6,
          29,
          50,
        ); // Came late, was outside then
        final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);

        await engine.processVehicleState(
          vehicleInside,
          nowUtc: t0,
          organizationId: 'org-1',
        );

        // Late event arrives out of order
        await engine.processVehicleState(
          vehicleOutside,
          nowUtc: tMinus10,
          organizationId: 'org-1',
        );

        await engine.processVehicleState(
          vehicleInside,
          nowUtc: t31,
          organizationId: 'org-1',
        );

        final result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.executed);
        expect(ledger.entries, hasLength(1));
      },
    );

    test(
      'sweepExpiredObligations is idempotent for prolonged absence',
      () async {
        await seedPlan(planRepo, 'c-1', 1);
        final state = makeExecState(windowEnd: DateTime.utc(2026, 3, 1, 7, 0));
        await repo.save(state);

        final afterExpiry1 = DateTime.utc(2026, 3, 1, 7, 1);
        await engine.sweepExpiredObligations(
          nowUtc: afterExpiry1,
          organizationId: 'org-1',
        );

        final afterExpiry2 = DateTime.utc(2026, 3, 1, 7, 10);
        await engine.sweepExpiredObligations(
          nowUtc: afterExpiry2,
          organizationId: 'org-1',
        );

        final result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.noShow);
        // Should still be 1 event in ledger, not 2
        expect(ledger.entries, hasLength(1));
      },
    );

    test(
      'delayed execution is rejected if already marked as no-show',
      () async {
        await seedPlan(planRepo, 'c-1', 1);
        final state = makeExecState(windowEnd: DateTime.utc(2026, 3, 1, 7, 0));
        await repo.save(state);

        // Sweep marks as no-show
        final afterExpiry = DateTime.utc(2026, 3, 1, 7, 1);
        await engine.sweepExpiredObligations(
          nowUtc: afterExpiry,
          organizationId: 'org-1',
        );

        // Vehicle arrives very late (after no-show)
        final vehicle = makeVehicleState();
        final tLate0 = DateTime.utc(2026, 3, 1, 7, 5, 0);
        final tLate31 = DateTime.utc(2026, 3, 1, 7, 5, 31);

        await engine.processVehicleState(
          vehicle,
          nowUtc: tLate0,
          organizationId: 'org-1',
        );
        await engine.processVehicleState(
          vehicle,
          nowUtc: tLate31,
          organizationId: 'org-1',
        );

        final result = await repo.findBySetId('set-1');
        expect(result!.status, ExecutionStatus.noShow);

        // Still only 1 ledger entry (the no-show)
        expect(ledger.entries, hasLength(1));
      },
    );

    test(
      'concurrent events for same setid do not duplicate execution',
      () async {
        await seedPlan(planRepo, 'c-1', 1);
        final state = makeExecState();
        await repo.save(state);

        final vehicle = makeVehicleState();
        final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
        final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);

        await engine.processVehicleState(
          vehicle,
          nowUtc: t0,
          organizationId: 'org-1',
        );

        // Fire 3 simultaneous events for t31
        await Future.wait([
          engine.processVehicleState(
            vehicle,
            nowUtc: t31,
            organizationId: 'org-1',
          ),
          engine.processVehicleState(
            vehicle,
            nowUtc: t31,
            organizationId: 'org-1',
          ),
          engine.processVehicleState(
            vehicle,
            nowUtc: t31,
            organizationId: 'org-1',
          ),
        ]);

        expect(ledger.entries, hasLength(1));
      },
    );
  });
}
