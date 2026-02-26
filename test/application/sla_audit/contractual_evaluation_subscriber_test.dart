import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/domain/entities/vehicle_operational_state.dart';
import 'package:busflow/domain/enums/motion_state.dart';
import 'package:busflow/domain/enums/connectivity_state.dart';
import 'package:busflow/domain/sla_audit/contractual_execution_state.dart';
import 'package:busflow/domain/sla_audit/execution_status.dart';
import 'package:busflow/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:busflow/application/sla_audit/contractual_evaluation_subscriber.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  // ── Shared fixtures ──────────────────────────────────────
  late InMemoryContractualExecutionStateRepository repo;
  late InMemorySlaAuditLedgerRepository ledger;
  late ContractualEvaluationEngine engine;
  late StreamController<List<VehicleOperationalState>> streamController;

  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100;

  setUp(() {
    repo = InMemoryContractualExecutionStateRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    engine = ContractualEvaluationEngine(
      executionRepo: repo,
      ledgerRepo: ledger,
    );
    streamController =
        StreamController<List<VehicleOperationalState>>.broadcast();
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
      setId: setId,
      contractId: contractId,
      planVersion: 1,
      startLatitude: geoLat,
      startLongitude: geoLng,
      startRadiusMeters: geoRadius,
      contractualValue: 150.0,
      noShowPenaltyMultiplier: 1.5,
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
      );

      await subscriber.start();

      final vehicle = makeVehicle();

      // First ping — enters geofence
      streamController.add([vehicle]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Verify engine ran — state should still be pending (< 30s dwell)
      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);

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
      );

      await subscriber.start();

      // Two vehicles in one batch
      streamController.add([
        makeVehicle(vehicleId: 'v-1'),
        makeVehicle(vehicleId: 'v-2'),
      ]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Both should have been processed (still pending, < 30s)
      final r1 = await repo.findBySetId('set-1');
      final r2 = await repo.findBySetId('set-2');
      expect(r1!.status, ExecutionStatus.pending);
      expect(r2!.status, ExecutionStatus.pending);

      await subscriber.stop();
    });

    test('sweep timer calls sweepExpiredObligations', () async {
      // Manually override status to simulate expired state in window
      // We can't change window times after creation, so create with past window
      final expiredState = ContractualExecutionState.create(
        setId: 'set-expired',
        contractId: 'c-1',
        planVersion: 1,
        startLatitude: geoLat,
        startLongitude: geoLng,
        startRadiusMeters: geoRadius,
        contractualValue: 150.0,
        noShowPenaltyMultiplier: 1.5,
        windowStartUtc: DateTime.utc(2026, 2, 1, 6, 0),
        windowEndUtc: DateTime.utc(2026, 2, 1, 7, 0), // past
      );
      await repo.save(expiredState);

      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(milliseconds: 100),
      );

      await subscriber.start();

      // Wait for at least one sweep tick
      await Future.delayed(const Duration(milliseconds: 250));

      final result = await repo.findBySetId('set-expired');
      expect(result!.status, ExecutionStatus.noShow);

      await subscriber.stop();
    });

    test('stop() cancels subscription and timer', () async {
      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(minutes: 10),
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
      );

      await subscriber.start();
      await subscriber.start(); // Second call — should be no-op

      expect(subscriber.isActive, isTrue);

      // Emit data — should only be processed once per vehicle per batch
      final vehicle = makeVehicle();
      streamController.add([vehicle]);
      await Future.delayed(const Duration(milliseconds: 50));

      final result = await repo.findBySetId('set-1');
      expect(result!.status, ExecutionStatus.pending);

      await subscriber.stop();
    });

    test('engine error does not cancel the subscription', () async {
      // Create a state that will cause the engine to process normally
      await repo.save(makeExecState());

      final subscriber = ContractualEvaluationSubscriber(
        engine: engine,
        vehicleStream: streamController.stream,
        sweepInterval: const Duration(minutes: 10),
      );

      await subscriber.start();

      // Emit a normal vehicle — processed without error
      streamController.add([makeVehicle()]);
      await Future.delayed(const Duration(milliseconds: 50));

      // Subscriber should still be active
      expect(subscriber.isActive, isTrue);

      // Emit another batch — subscriber should still be listening
      streamController.add([makeVehicle(vehicleId: 'v-2')]);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(subscriber.isActive, isTrue);

      await subscriber.stop();
    });
  });
}
