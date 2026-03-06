import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:busflow/application/sla_audit/alert_derivation_service.dart';
import 'package:busflow/application/sla_audit/alert_service.dart';
import 'package:busflow/domain/entities/vehicle_operational_state.dart';
import 'package:busflow/domain/enums/motion_state.dart';
import 'package:busflow/domain/enums/connectivity_state.dart';
import 'package:busflow/domain/sla_audit/contractual_service_execution.dart';
import 'package:busflow/domain/sla_audit/contractual_execution_state.dart';
import 'package:busflow/domain/sla_audit/execution_status.dart';
import 'package:busflow/domain/sla_audit/plan_declaration.dart';
import 'package:busflow/domain/sla_audit/rule_snapshot.dart';
import 'package:busflow/domain/sla_audit/operational_alert.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_operational_alert_repository.dart';

/// Phase 4 Compliance Review — Operational Alerts
void main() {
  const geoLat = -23.5505;
  const geoLng = -46.6333;
  const geoRadius = 100;

  late InMemoryContractualExecutionStateRepository repo;
  late InMemoryPlanDeclarationRepository planRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemoryEvaluationTraceRepository traceRepo;
  late InMemoryOperationalAlertRepository alertRepo;
  late ContractualEvaluationEngine engine;

  ContractualExecutionState makeState({String setId = 'set-1'}) {
    return ContractualExecutionState.create(
      organizationId: 'org-1',
      setId: setId,
      contractId: 'c-1',
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

  VehicleOperationalState makeVehicle() {
    return VehicleOperationalState(
      vehicleId: 'v-1',
      tripId: 'trip-1',
      latitude: geoLat,
      longitude: geoLng,
      smoothedSpeed: 0.0,
      motionState: MotionState.stopped,
      connectivityState: ConnectivityState.healthy,
      lastRawPingAt: DateTime.utc(2026, 3, 1, 6, 30),
      stateChangedAt: DateTime.utc(2026, 3, 1, 6, 30),
      confidence: 1.0,
      source: 'test',
    );
  }

  Future<void> seedPlan() async {
    await planRepo.save(
      PlanDeclaration.create(
        organizationId: 'org-1',
        contractId: 'c-1',
        planVersion: 1,
        declaredAtUtc: DateTime.utc(2026, 1, 1),
        declaredByUserId: 'user-1',
        originalFileHash: 'hash-1',
        services: [
          ContractualServiceExecution.create(
            contractId: 'c-1',
            scheduledStartTimeUtc: DateTime.utc(2026, 3, 1, 6, 0),
            scheduledEndTimeUtc: DateTime.utc(2026, 3, 1, 7, 0),
            startLatitude: geoLat,
            startLongitude: geoLng,
            startRadiusMeters: geoRadius,
            endLatitude: -23.56,
            endLongitude: -46.64,
            endRadiusMeters: geoRadius,
            contractualValue: 150.0,
            noShowPenaltyMultiplier: 1.5,
          ),
        ],
        ruleSnapshot: const RuleSnapshot([]),
      ),
    );
  }

  setUp(() async {
    repo = InMemoryContractualExecutionStateRepository();
    planRepo = InMemoryPlanDeclarationRepository();
    ledger = InMemorySlaAuditLedgerRepository();
    traceRepo = InMemoryEvaluationTraceRepository();
    alertRepo = InMemoryOperationalAlertRepository();

    engine = ContractualEvaluationEngine(
      executionRepo: repo,
      planRepo: planRepo,
      ledgerRepo: ledger,
      traceRepo: traceRepo,
      alertRepo: alertRepo,
    );

    await seedPlan();
  });

  group('Phase 4 Compliance Review', () {
    // ══════════════════════════════════════════════════════════
    // 1. ALERT DERIVATION FROM EXECUTION TRANSITIONS
    // ══════════════════════════════════════════════════════════

    test('C4-01: NoShow produces CRITICAL alert', () async {
      await repo.save(makeState());

      await engine.sweepExpiredObligations(
        nowUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      final alerts = alertRepo.alerts;
      expect(alerts, isNotEmpty);
      expect(alerts.first.alertType, equals('NO_SHOW'));
      expect(alerts.first.severity, equals('CRITICAL'));
      expect(alerts.first.status, equals('ACTIVE'));
      expect(alerts.first.organizationId, equals('org-1'));
      expect(alerts.first.entityId, equals('set-1'));
    });

    test('C4-02: successful binding does NOT produce alert', () async {
      await repo.save(makeState());

      final v = makeVehicle();
      await engine.processVehicleState(
        v,
        nowUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );
      await engine.processVehicleState(
        v,
        nowUtc: DateTime.utc(2026, 3, 1, 6, 30, 31),
      );

      final state = await repo.findBySetId('set-1');
      expect(state!.status, ExecutionStatus.executed);

      // No alert for successful execution without penalties
      final alerts = alertRepo.alerts;
      expect(
        alerts,
        isEmpty,
        reason:
            'Successful execution without penalties must not produce alerts',
      );
    });

    // ══════════════════════════════════════════════════════════
    // 2. CAUSAL LINKAGE
    // ══════════════════════════════════════════════════════════

    test('C4-03: alert references ledger event and trace', () async {
      await repo.save(makeState());

      await engine.sweepExpiredObligations(
        nowUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      final alert = alertRepo.alerts.first;
      expect(alert.triggeringEventId, isNotNull);
      expect(alert.traceId, isNotNull);

      // Verify the causal chain exists
      final traces = await traceRepo.findByEntityId('set-1');
      expect(
        traces.any((t) => t.id == alert.traceId),
        isTrue,
        reason: 'Alert traceId must reference a persisted trace',
      );
    });

    // ══════════════════════════════════════════════════════════
    // 3. IDEMPOTENCY (LEDGER-EVENT BASED)
    // ══════════════════════════════════════════════════════════

    test(
      'C4-04: duplicate alert from same ledger event is suppressed',
      () async {
        await repo.save(makeState());

        await engine.sweepExpiredObligations(
          nowUtc: DateTime.utc(2026, 3, 1, 8, 0),
        );

        final alert = alertRepo.alerts.first;

        // Attempt to save the same alert again (simulates replay)
        await alertRepo.save(
          OperationalAlert(
            id: '',
            organizationId: alert.organizationId,
            entityId: alert.entityId,
            contractId: alert.contractId,
            alertType: alert.alertType,
            severity: alert.severity,
            triggeredAtUtc: alert.triggeredAtUtc,
            triggeringEventId: alert.triggeringEventId,
            traceId: alert.traceId,
          ),
        );

        // Should still have only one alert
        expect(
          alertRepo.alerts.length,
          equals(1),
          reason: 'Duplicate alert from same ledger event must be suppressed',
        );
      },
    );

    // ══════════════════════════════════════════════════════════
    // 4. ALERT LIFECYCLE (SERVICE-CONTROLLED)
    // ══════════════════════════════════════════════════════════

    test('C4-05: ACTIVE → ACKNOWLEDGED → RESOLVED lifecycle', () async {
      await repo.save(makeState());

      await engine.sweepExpiredObligations(
        nowUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      final alertId = alertRepo.alerts.first.id;
      final service = AlertService(repo: alertRepo);

      // Acknowledge
      await service.acknowledge(
        alertId: alertId,
        userId: 'operator-1',
        atUtc: DateTime.utc(2026, 3, 1, 8, 5),
      );

      var alert = await alertRepo.findById(alertId);
      expect(alert!.status, equals('ACKNOWLEDGED'));
      expect(alert.acknowledgedByUserId, equals('operator-1'));
      expect(alert.acknowledgedAtUtc, isNotNull);

      // Resolve
      await service.resolve(
        alertId: alertId,
        atUtc: DateTime.utc(2026, 3, 1, 9, 0),
      );

      alert = await alertRepo.findById(alertId);
      expect(alert!.status, equals('RESOLVED'));
      expect(alert.resolvedAtUtc, isNotNull);
    });

    test('C4-06: invalid lifecycle transitions are rejected', () async {
      await repo.save(makeState());

      await engine.sweepExpiredObligations(
        nowUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      final alertId = alertRepo.alerts.first.id;
      final service = AlertService(repo: alertRepo);

      // Cannot resolve before acknowledging
      expect(
        () => service.resolve(
          alertId: alertId,
          atUtc: DateTime.utc(2026, 3, 1, 8, 5),
        ),
        throwsStateError,
      );

      // Acknowledge first
      await service.acknowledge(
        alertId: alertId,
        userId: 'op-1',
        atUtc: DateTime.utc(2026, 3, 1, 8, 5),
      );

      // Cannot re-acknowledge
      expect(
        () => service.acknowledge(
          alertId: alertId,
          userId: 'op-2',
          atUtc: DateTime.utc(2026, 3, 1, 8, 10),
        ),
        throwsStateError,
      );
    });

    // ══════════════════════════════════════════════════════════
    // 5. TENANT ISOLATION
    // ══════════════════════════════════════════════════════════

    test('C4-07: findActive scopes alerts by organization', () async {
      await repo.save(makeState());

      await engine.sweepExpiredObligations(
        nowUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      final org1Alerts = await alertRepo.findActive('org-1');
      final org2Alerts = await alertRepo.findActive('org-2');

      expect(org1Alerts, isNotEmpty);
      expect(
        org2Alerts,
        isEmpty,
        reason: 'Alerts must be scoped by organization_id',
      );
    });

    // ══════════════════════════════════════════════════════════
    // 6. DOMAIN SOVEREIGNTY
    // ══════════════════════════════════════════════════════════

    test('C4-08: OperationalAlert is pure Dart', () {
      final alert = OperationalAlert(
        id: 'alert-001',
        organizationId: 'org-1',
        entityId: 'set-1',
        contractId: 'c-1',
        alertType: 'NO_SHOW',
        severity: 'CRITICAL',
        triggeredAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      // Domain model construction with no Flutter imports
      expect(alert.organizationId, equals('org-1'));
      expect(alert.alertType, equals('NO_SHOW'));

      // Lifecycle transitions are pure domain operations
      final acked = alert.acknowledge('user-1', DateTime.utc(2026, 3, 1, 8, 5));
      expect(acked.status, equals('ACKNOWLEDGED'));

      final resolved = acked.resolve(DateTime.utc(2026, 3, 1, 9, 0));
      expect(resolved.status, equals('RESOLVED'));
      expect(resolved.resolvedAtUtc, isNotNull);
    });

    // ══════════════════════════════════════════════════════════
    // 7. ALERT DERIVATION SERVICE (UNIT)
    // ══════════════════════════════════════════════════════════

    test('C4-09: AlertDerivationService maps correct types and severities', () {
      // NoShow → CRITICAL
      final noShowState = ContractualExecutionState.reconstitute(
        id: 'id-1',
        organizationId: 'org-1',
        setId: 'set-1',
        contractId: 'c-1',
        planVersion: 1,
        startLatitude: geoLat,
        startLongitude: geoLng,
        startRadiusMeters: geoRadius,
        contractualValue: 150.0,
        noShowPenaltyMultiplier: 1.5,
        windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
        windowEndUtc: DateTime.utc(2026, 3, 1, 7, 0),
        status: ExecutionStatus.noShow,
        createdAtUtc: DateTime.utc(2026, 3, 1, 6, 0),
        lastEvaluatedAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
        statusLastUpdatedAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
        finalizedAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      final noShowAlert = AlertDerivationService.deriveFrom(
        state: noShowState,
        decisions: const [],
        evaluatedAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );
      expect(noShowAlert, isNotNull);
      expect(noShowAlert!.alertType, equals('NO_SHOW'));
      expect(noShowAlert.severity, equals('CRITICAL'));

      // EvidenceGap → WARNING
      final gapState = ContractualExecutionState.reconstitute(
        id: 'id-2',
        organizationId: 'org-1',
        setId: 'set-2',
        contractId: 'c-1',
        planVersion: 1,
        startLatitude: geoLat,
        startLongitude: geoLng,
        startRadiusMeters: geoRadius,
        contractualValue: 150.0,
        noShowPenaltyMultiplier: 1.5,
        windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
        windowEndUtc: DateTime.utc(2026, 3, 1, 7, 0),
        status: ExecutionStatus.evidenceGap,
        createdAtUtc: DateTime.utc(2026, 3, 1, 6, 0),
        lastEvaluatedAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
        statusLastUpdatedAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
        finalizedAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      final gapAlert = AlertDerivationService.deriveFrom(
        state: gapState,
        decisions: const [],
        evaluatedAtUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );
      expect(gapAlert, isNotNull);
      expect(gapAlert!.alertType, equals('EVIDENCE_GAP'));
      expect(gapAlert.severity, equals('WARNING'));

      // Pending → null
      final pendingState = ContractualExecutionState.reconstitute(
        id: 'id-3',
        organizationId: 'org-1',
        setId: 'set-3',
        contractId: 'c-1',
        planVersion: 1,
        startLatitude: geoLat,
        startLongitude: geoLng,
        startRadiusMeters: geoRadius,
        contractualValue: 150.0,
        noShowPenaltyMultiplier: 1.5,
        windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
        windowEndUtc: DateTime.utc(2026, 3, 1, 7, 0),
        status: ExecutionStatus.pending,
        createdAtUtc: DateTime.utc(2026, 3, 1, 6, 0),
        lastEvaluatedAtUtc: DateTime.utc(2026, 3, 1, 6, 30),
        statusLastUpdatedAtUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );

      final pendingAlert = AlertDerivationService.deriveFrom(
        state: pendingState,
        decisions: const [],
        evaluatedAtUtc: DateTime.utc(2026, 3, 1, 6, 30),
      );
      expect(
        pendingAlert,
        isNull,
        reason: 'Pending states must not produce alerts',
      );
    });

    // ══════════════════════════════════════════════════════════
    // 8. SINGLE DECISION ENGINE
    // ══════════════════════════════════════════════════════════

    test('C4-10: alerts originate exclusively from engine pipeline', () async {
      await repo.save(makeState());

      // Before engine runs, no alerts
      expect(alertRepo.alerts, isEmpty);

      // Engine runs sweep
      await engine.sweepExpiredObligations(
        nowUtc: DateTime.utc(2026, 3, 1, 8, 0),
      );

      // Alert produced by engine pipeline
      expect(alertRepo.alerts, isNotEmpty);
      expect(alertRepo.alerts.first.alertType, equals('NO_SHOW'));
    });
  });
}
