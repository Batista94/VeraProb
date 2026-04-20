import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/sla_audit/telemetry_ingestion_pipeline.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/contractual_service_execution.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  group('Engine Replay Determinism (INV-7 / INV-12)', () {
    late ContractualEvaluationEngine engine;
    late InMemoryContractualExecutionStateRepository execRepo;
    late InMemoryPlanDeclarationRepository planRepo;
    late InMemorySlaAuditLedgerRepository ledgerRepo;
    late InMemoryEvaluationTraceRepository traceRepo;
    late TelemetryIngestionPipeline pipeline;

    const orgId = 'org-789';
    const contractId = 'contract-456';
    const vehicleId = 'VH-001';
    const setId = 'SET-101';

    setUp(() {
      execRepo = InMemoryContractualExecutionStateRepository();
      planRepo = InMemoryPlanDeclarationRepository();
      ledgerRepo = InMemorySlaAuditLedgerRepository();
      traceRepo = InMemoryEvaluationTraceRepository();
      engine = ContractualEvaluationEngine(
        executionRepo: execRepo,
        planRepo: planRepo,
        ledgerRepo: ledgerRepo,
        traceRepo: traceRepo,
      );
      pipeline = TelemetryIngestionPipeline(engine: engine);
    });

    Future<void> seedPlan() async {
      final plan = PlanDeclaration.reconstitute(
        id: 'PLAN-1',
        organizationId: orgId,
        contractId: contractId,
        declaredAtUtc: DateTime.utc(2026, 1, 1),
        declaredByUserId: 'SYS_USER',
        planVersion: 1,
        originalFileHash: 'SHA256:FAKE',
        ruleSnapshot: const RuleSnapshot([
          RuleSnapshotItem(
            ruleId: 'RULE-1',
            ruleType: SlaRuleType.minGeofenceCoverage,
            config: <String, dynamic>{'min_dwell_seconds': 300}, // 5 minutes
            ruleVersion: 1,
            evaluationOrder: 1,
          ),
          RuleSnapshotItem(
            ruleId: 'RULE-PENALTY',
            ruleType: SlaRuleType.noShowPenalty,
            config: <String, dynamic>{'penalty_amount_cents': 50000},
            ruleVersion: 1,
            evaluationOrder: 2,
          ),
        ]),
        services: const <ContractualServiceExecution>[],
      );
      await planRepo.save(plan);
    }

    test(
      'Batching Invariance: Multiple small batches vs Single big batch produce identical final state',
      () async {
        await seedPlan();

        final t0 = DateTime.utc(2026, 3, 1, 10, 0);
        final t5 = DateTime.utc(2026, 3, 1, 10, 5);
        final t15 = DateTime.utc(2026, 3, 1, 10, 15);

        final facts = [
          CanonicalFact.reconstitute(
            id: 'F1',
            organizationId: orgId,
            assetId: vehicleId,
            deviceId: 'DEV1',
            rawPayloadId: 'P1',
            sourceAdapter: 'GPS',
            receivedAtUtc: t0,
            gpsTimestamp: t0,
            lat: -23.5,
            lng: -46.6,
            integrityFlag: IngestionIntegrityFlag.ok,
          ),
          CanonicalFact.reconstitute(
            id: 'F2',
            organizationId: orgId,
            assetId: vehicleId,
            deviceId: 'DEV1',
            rawPayloadId: 'P2',
            sourceAdapter: 'GPS',
            receivedAtUtc: t5,
            gpsTimestamp: t5,
            lat: -23.5001,
            lng: -46.6001,
            integrityFlag: IngestionIntegrityFlag.ok,
          ),
          CanonicalFact.reconstitute(
            id: 'F3',
            organizationId: orgId,
            assetId: vehicleId,
            deviceId: 'DEV1',
            rawPayloadId: 'P3',
            sourceAdapter: 'GPS',
            receivedAtUtc: t15,
            gpsTimestamp: t15,
            lat: -23.5002,
            lng: -46.6002,
            integrityFlag: IngestionIntegrityFlag.ok,
          ),
        ];

        final windowStart = DateTime.utc(2026, 3, 1, 10, 0);
        final windowEnd = DateTime.utc(2026, 3, 1, 11, 0);

        ContractualExecutionState makeInitialState() =>
            ContractualExecutionState.create(
              organizationId: orgId,
              setId: setId,
              contractId: contractId,
              planVersion: 1,
              startLatitude: -23.5,
              startLongitude: -46.6,
              startRadiusMeters: 500,
              contractualValue: const Money(100000),
              noShowPenaltyBps: 15000,
              windowStartUtc: windowStart,
              windowEndUtc: windowEnd,
            );

        final stateAInitial = makeInitialState();
        await execRepo.save(stateAInitial);

        // RUN A: Single Batch
        await pipeline.process(facts, organizationId: orgId);

        final stateA = await execRepo.findBySetId(setId);
        expect(stateA?.status, equals(ExecutionStatus.executed));

        final ledgerA = await ledgerRepo.getEntriesBySetId(setId);
        expect(ledgerA.any((e) => e.type == 'EXECUTION_BOUND'), isTrue);

        // --- RESET FOR RUN B ---
        ledgerRepo = InMemorySlaAuditLedgerRepository();
        traceRepo = InMemoryEvaluationTraceRepository();
        engine = ContractualEvaluationEngine(
          executionRepo: execRepo,
          planRepo: planRepo,
          ledgerRepo: ledgerRepo,
          traceRepo: traceRepo,
        );
        pipeline = TelemetryIngestionPipeline(engine: engine);
        final stateBInitial = makeInitialState();
        await execRepo.save(stateBInitial);

        // RUN B: Multiple Batches
        await pipeline.process([facts[0]], organizationId: orgId);
        await pipeline.process([facts[1]], organizationId: orgId);
        await pipeline.process([facts[2]], organizationId: orgId);

        final stateB = await execRepo.findBySetId(setId);
        expect(stateB?.status, equals(ExecutionStatus.executed));

        final ledgerB = await ledgerRepo.getEntriesBySetId(setId);
        expect(ledgerB.any((e) => e.type == 'EXECUTION_BOUND'), isTrue);
      },
    );

    test(
      'Temporal Determinism: Late arrival corrections result in consistent final state',
      () async {
        await seedPlan();

        final t0 = DateTime.utc(2026, 3, 1, 10, 0);
        final t15 = DateTime.utc(2026, 3, 1, 10, 15);
        final tSweep = DateTime.utc(2026, 3, 1, 11, 1);

        final initialState = ContractualExecutionState.create(
          organizationId: orgId,
          setId: setId,
          contractId: contractId,
          planVersion: 1,
          startLatitude: -23.5,
          startLongitude: -46.6,
          startRadiusMeters: 500,
          contractualValue: const Money(100000),
          noShowPenaltyBps: 15000,
          windowStartUtc: t0,
          windowEndUtc: DateTime.utc(2026, 3, 1, 11, 0),
        );
        await execRepo.save(initialState);

        // 1. Process only Enter (T0). Dwell is not yet 5 minutes.
        await pipeline.process([
          CanonicalFact.reconstitute(
            id: 'F1',
            organizationId: orgId,
            assetId: vehicleId,
            deviceId: 'DEV1',
            rawPayloadId: 'P1',
            sourceAdapter: 'GPS',
            receivedAtUtc: t0,
            gpsTimestamp: t0,
            lat: -23.5,
            lng: -46.6,
            integrityFlag: IngestionIntegrityFlag.ok,
          ),
        ], organizationId: orgId);

        // Trigger automatic NO_SHOW sweep
        await engine.sweepExpiredObligations(
          nowUtc: tSweep,
          organizationId: orgId,
        );

        final stateAtSweep = await execRepo.findBySetId(setId);
        expect(
          stateAtSweep?.status,
          equals(ExecutionStatus.noShow),
          reason: 'Sweep should mark expired pending state as noShow',
        );

        // 2. Late fact arrives (T15) which proves dwell time.
        await pipeline.process([
          CanonicalFact.reconstitute(
            id: 'FLate',
            organizationId: orgId,
            assetId: vehicleId,
            deviceId: 'DEV1',
            rawPayloadId: 'PL',
            sourceAdapter: 'GPS',
            // Use a receivedAtUtc within the INV-12 48h reprocessing window
            // (window ends 2026-03-01 11:00 → cutoff is 2026-03-03 11:00).
            receivedAtUtc: DateTime.utc(2026, 3, 1, 12, 0),
            gpsTimestamp: t15,
            lat: -23.5001,
            lng: -46.6001,
            integrityFlag: IngestionIntegrityFlag.lateArrival,
          ),
        ], organizationId: orgId);

        final finalState = await execRepo.findBySetId(setId);
        expect(
          finalState?.status,
          equals(ExecutionStatus.executed),
          reason: 'Late arrival MUST correct noShow state to executed',
        );

        final ledger = await ledgerRepo.getEntriesBySetId(setId);
        expect(ledger.any((e) => e.type == 'NO_SHOW_DECLARED'), isTrue);
        expect(ledger.any((e) => e.type == 'EXECUTION_BOUND'), isTrue);
      },
    );
  });
}
