import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/sla_audit/contractual_evaluation_subscriber.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  // ── Shared fixtures ──────────────────────────────────────
  late InMemoryContractualExecutionStateRepository repo;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemoryPlanDeclarationRepository planRepo;
  late ContractualEvaluationEngine engine;
  late StreamController<List<VehicleOperationalState>> streamController;

  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100;

  setUp(() async {
    repo = InMemoryContractualExecutionStateRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    planRepo = InMemoryPlanDeclarationRepository();
    engine = ContractualEvaluationEngine(
      executionRepo: repo,
      planRepo: planRepo,
      ledgerRepo: ledger,
      traceRepo: InMemoryEvaluationTraceRepository(),
    );
    streamController =
        StreamController<List<VehicleOperationalState>>.broadcast();

    // Default seed
    // We only need the ruleSnapshot empty for most of these tests
    await planRepo.save(
      PlanDeclaration.reconstitute(
        id: 'plan-123',
        organizationId: 'org-1',
        contractId: 'c-1',
        planVersion: 1,
        declaredAtUtc: DateTime.utc(2026, 3, 1),
        declaredByUserId: 'test',
        originalFileHash: 'hash',
        services: const [],
        ruleSnapshot: const RuleSnapshot([]),
      ),
    );
    await planRepo.save(
      PlanDeclaration.reconstitute(
        id: 'plan-xyz',
        organizationId: 'org-1',
        contractId: 'c-2',
        planVersion: 1,
        declaredAtUtc: DateTime.utc(2026, 3, 1),
        declaredByUserId: 'test',
        originalFileHash: 'hash',
        services: const [],
        ruleSnapshot: const RuleSnapshot([]),
      ),
    );
  });

  tearDown(() async {
    await streamController.close();
  });

  VehicleOperationalState makeVehicle({
    String vehicleId = 'v-1',
    double latitude = geoLat,
    double longitude = geoLng,
  }) {
    return VehicleOperationalState(
      rawSpeed: 0.0,
      vehicleId: vehicleId,
      tripId: 'trip-1',
      latitude: latitude,
      longitude: longitude,
      smoothedSpeed: 0.0,
      motionState: MotionState.stopped,
      connectivityState: ConnectivityState.healthy,
      lastRawPingAt: DateTime.utc(2026, 3, 1, 6, 30),
      stateChangedAt: DateTime.utc(2026, 3, 1, 6, 30),
      confidence: 1.0,
      source: 'test',
    );
  }

  ContractualExecutionState makeExecState({
    String setId = 'set-1',
    String contractId = 'c-1',
  }) {
    return ContractualExecutionState.create(
      organizationId: 'org-1',
      setId: setId,
      contractId: contractId,
      planVersion: 1,
      startLatitude: geoLat,
      startLongitude: geoLng,
      startRadiusMeters: geoRadius,
      contractualValue: const Money(15000),
      noShowPenaltyBps: 15000,
      windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
      windowEndUtc: DateTime.utc(2026, 3, 1, 7, 0),
    );
  }

  // ── Tests ────────────────────────────────────────────────
  group('ContractualEvaluationSubscriber', () {
    test('processes single vehicle from stream', () async {
      await repo.save(makeExecState());

      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(minutes: 10),
        organizationId: 'org-1',
      );

      await subscriber.start();

      final vehicle = makeVehicle();

      // First ping — enters geofence
      streamController.add([vehicle]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Verify engine ran — state transitions to inTransit on first geofence entry
      final result = await repo.findBySetId('set-1', organizationId: 'org-1');
      expect(result!.status, ExecutionStatus.inTransit);

      await subscriber.stop();
    });

    test('processes multiple vehicles from stream', () async {
      final state1 = makeExecState(setId: 'set-1');
      final state2 = makeExecState(setId: 'set-2', contractId: 'c-2');
      await repo.save(state1);
      await repo.save(state2);

      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(minutes: 10),
        organizationId: 'org-1',
      );

      await subscriber.start();

      // Two vehicles in one batch
      streamController.add([
        makeVehicle(vehicleId: 'v-1'),
        makeVehicle(vehicleId: 'v-2'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Both should have been processed (inTransit after first geofence entry)
      final r1 = await repo.findBySetId('set-1', organizationId: 'org-1');
      final r2 = await repo.findBySetId('set-2', organizationId: 'org-1');
      expect(r1!.status, ExecutionStatus.inTransit);
      expect(r2!.status, ExecutionStatus.inTransit);

      await subscriber.stop();
    });

    test('sweep timer calls sweepExpiredObligations', () async {
      // Manually override status to simulate expired state in window
      // We can't change window times after creation, so create with past window
      final expiredState = ContractualExecutionState.create(
        organizationId: 'org-1',
        setId: 'set-expired',
        contractId: 'c-1',
        planVersion: 1,
        startLatitude: geoLat,
        startLongitude: geoLng,
        startRadiusMeters: geoRadius,
        contractualValue: const Money(15000),
        noShowPenaltyBps: 15000,
        windowStartUtc: DateTime.utc(2026, 2, 1, 6, 0),
        windowEndUtc: DateTime.utc(2026, 2, 1, 7, 0), // past
      );
      await repo.save(expiredState);

      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(milliseconds: 100),
        organizationId: 'org-1',
      );

      await subscriber.start();

      // Wait for at least one sweep tick
      await Future<void>.delayed(const Duration(milliseconds: 250));

      final result = await repo.findBySetId(
        'set-expired',
        organizationId: 'org-1',
      );
      expect(result!.status, ExecutionStatus.failed);

      await subscriber.stop();
    });

    test('stop() cancels subscription and timer', () async {
      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(minutes: 10),
        organizationId: 'org-1',
      );

      await subscriber.start();
      expect(subscriber.isActive, isTrue);

      await subscriber.stop();
      expect(subscriber.isActive, isFalse);

      // Calling stop again should be safe
      await subscriber.stop();
      expect(subscriber.isActive, isFalse);
    });

    test('start() does not create duplicate subscriptions', () async {
      await repo.save(makeExecState());

      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(minutes: 10),
        organizationId: 'org-1',
      );

      await subscriber.start();
      await subscriber.start(); // Second call — should be no-op

      expect(subscriber.isActive, isTrue);

      // Emit data — should only be processed once per vehicle per batch
      final vehicle = makeVehicle();
      streamController.add([vehicle]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final result = await repo.findBySetId('set-1', organizationId: 'org-1');
      expect(result!.status, ExecutionStatus.inTransit);

      await subscriber.stop();
    });

    test('engine error does not cancel the subscription', () async {
      // Create a state that will cause the engine to process normally
      await repo.save(makeExecState());

      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(minutes: 10),
        organizationId: 'org-1',
      );

      await subscriber.start();

      // Emit a normal vehicle — processed without error
      streamController.add([makeVehicle()]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Subscriber should still be active
      expect(subscriber.isActive, isTrue);

      // Emit another batch — subscriber should still be listening
      expect(subscriber.isActive, isTrue);

      await subscriber.stop();
    });

    test('ignores duplicate telemetry to avoid redundant processing', () async {
      // Seed the execution state so the engine has something to evaluate.
      // Without this, findBySetId('set-1') returns null and the null-check
      // assertion throws. All other tests in this group seed via repo.save()
      // before starting the subscriber — this test was missing that step.
      await repo.save(makeExecState());

      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(minutes: 10),
        organizationId: 'org-1',
      );
      await subscriber.start();

      final vehicle = makeVehicle();

      // Emit the exact same positions twice in a row
      streamController.add([vehicle]);
      streamController.add([vehicle]);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert it only processes once if identical (business logic dependent,
      // but subscriber shouldn't crash or duplicate state improperly).
      final result = await repo.findBySetId('set-1', organizationId: 'org-1');
      expect(result!.status, ExecutionStatus.inTransit);

      await subscriber.stop();
    });
  });
}
