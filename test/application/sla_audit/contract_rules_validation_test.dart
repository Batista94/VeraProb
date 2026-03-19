import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/domain/entities/vehicle_operational_state.dart';
import 'package:veraprob/domain/enums/motion_state.dart';
import 'package:veraprob/domain/enums/connectivity_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  group('Phase 2 Validation: Contract Rules & Configurable Determinism', () {
    late InMemoryContractualExecutionStateRepository execRepo;
    late InMemoryPlanDeclarationRepository planRepo;
    late InMemorySlaAuditLedgerRepository ledgerRepo;
    late ContractualEvaluationEngine engine;

    const geoLat = -23.5505;
    const geoLng = -46.6333;
    const geoRadius = 100;

    setUp(() {
      execRepo = InMemoryContractualExecutionStateRepository();
      planRepo = InMemoryPlanDeclarationRepository();
      ledgerRepo = InMemorySlaAuditLedgerRepository();
      engine = ContractualEvaluationEngine(
        executionRepo: execRepo,
        planRepo: planRepo,
        ledgerRepo: ledgerRepo,
        traceRepo: InMemoryEvaluationTraceRepository(),
      );
    });

    Future<void> declarePlanWithRules(
      String orgId,
      String contractId,
      int version,
      int dwellSeconds,
    ) async {
      final rules = RuleSnapshot([
        RuleSnapshotItem(
          ruleId: 'rule-$version',
          ruleType: SlaRuleType.minGeofenceCoverage,
          config: {'min_dwell_seconds': dwellSeconds},
          ruleVersion: version,
          evaluationOrder: 1,
        ),
      ]);

      final declaration = PlanDeclaration.create(
        organizationId: orgId,
        contractId: contractId,
        planVersion: version,
        declaredAtUtc: DateTime.utc(2026, 1, 1),
        declaredByUserId: 'admin-$orgId',
        originalFileHash: 'hash-v$version',
        services: [
          ContractualServiceExecution.create(
            contractId: contractId,
            scheduledStartTimeUtc: DateTime.utc(2026, 3, 1, 6, 0),
            scheduledEndTimeUtc: DateTime.utc(2026, 3, 1, 7, 0),
            startLatitude: geoLat,
            startLongitude: geoLng,
            startRadiusMeters: geoRadius,
            endLatitude: -23.5600,
            endLongitude: -46.6400,
            endRadiusMeters: 100,
            contractualValue: Money.fromDouble(150.0),
            noShowPenaltyMultiplier: 1.5,
          ),
        ],
        ruleSnapshot: rules,
      );
      await planRepo.save(declaration);

      final state = ContractualExecutionState.create(
        organizationId: orgId,
        setId: declaration.services.first.setId,
        contractId: contractId,
        planVersion: version,
        startLatitude: geoLat,
        startLongitude: geoLng,
        startRadiusMeters: geoRadius,
        contractualValue: Money.fromDouble(150.0),
        noShowPenaltyMultiplier: 1.5,
        windowStartUtc: DateTime.utc(2026, 3, 1, 5, 45),
        windowEndUtc: DateTime.utc(2026, 3, 1, 7, 15),
      );
      await execRepo.save(state);
    }

    VehicleOperationalState createPing(DateTime time) {
      return VehicleOperationalState(
        vehicleId: 'bus-1',
        tripId: 'trip-1',
        latitude: geoLat,
        longitude: geoLng,
        smoothedSpeed: 0.0,
        motionState: MotionState.stopped,
        connectivityState: ConnectivityState.healthy,
        lastRawPingAt: time,
        stateChangedAt: time,
        confidence: 1.0,
        source: 'gps',
      );
    }

    test(
      'Scenario 2.1: The Rule Time-Travel Test (Deterministic Replay)',
      () async {
        // Setup v1 Rules (Strict: 30 seconds)
        await declarePlanWithRules('org-1', 'contract-v1', 1, 30);

        // Setup v2 Rules (Lax: 5 seconds)
        await declarePlanWithRules('org-1', 'contract-v2', 2, 5);

        final t0 = DateTime.utc(2026, 3, 1, 6, 0, 0);
        final t10 = DateTime.utc(
          2026,
          3,
          1,
          6,
          0,
          10,
        ); // Vehicle stayed for 10 seconds

        // Replay telemetry against the Engine
        await engine.processVehicleState(createPing(t0), nowUtc: t0, organizationId: 'org-1');
        await engine.processVehicleState(createPing(t10), nowUtc: t10, organizationId: 'org-1');

        // Fetch the execution states
        final stateV1 = (await execRepo.findByContract('contract-v1', organizationId: 'org-1')).first;
        final stateV2 = (await execRepo.findByContract('contract-v2', organizationId: 'org-1')).first;

        // Assert Determinism:
        // Even though the same physical vehicle telemetry was fed to the engine at exactly the same time,
        // the outcomes perfectly match the historical Rule Snapshots embedded in their respective plans.
        expect(
          stateV1.status,
          ExecutionStatus.pending,
          reason: 'v1 requires 30s, vehicle left at 10s',
        );
        expect(
          stateV2.status,
          ExecutionStatus.executed,
          reason: 'v2 only requires 5s, vehicle stayed 10s',
        );
      },
    );

    test('Scenario 2.2: Dual-Tenant Rule Isolation', () async {
      // Org A requires 60 seconds
      await declarePlanWithRules('org-a', 'contract-a', 1, 60);
      // Org B requires 10 seconds
      await declarePlanWithRules('org-b', 'contract-b', 1, 10);

      final t0 = DateTime.utc(2026, 3, 1, 6, 0, 0);
      final t15 = DateTime.utc(
        2026,
        3,
        1,
        6,
        0,
        15,
      ); // Vehicle stayed for 15 seconds

      // Identical telemetry fed into each tenant's engine boundary separately.
      // The isolation test verifies that the same physical vehicle, evaluated
      // under org-a rules (60s) vs org-b rules (10s), produces different outcomes.
      await engine.processVehicleState(createPing(t0), nowUtc: t0, organizationId: 'org-a');
      await engine.processVehicleState(createPing(t15), nowUtc: t15, organizationId: 'org-a');
      await engine.processVehicleState(createPing(t0), nowUtc: t0, organizationId: 'org-b');
      await engine.processVehicleState(createPing(t15), nowUtc: t15, organizationId: 'org-b');

      final stateA = (await execRepo.findByContract('contract-a', organizationId: 'org-a')).first;
      final stateB = (await execRepo.findByContract('contract-b', organizationId: 'org-b')).first;

      // Verification of tenant boundary isolation inside identical compute pipeline
      expect(
        stateA.status,
        ExecutionStatus.pending,
        reason: 'Org A strict threshold (60) not met',
      );
      expect(
        stateB.status,
        ExecutionStatus.executed,
        reason: 'Org B lax threshold (10) was met',
      );
    });
  });
}
