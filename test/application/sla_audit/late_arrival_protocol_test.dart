import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/sla_audit/telemetry_ingestion_pipeline.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_asset_status_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  group('INV-12: Deterministic Late-Arrival Replay', () {
    late InMemoryContractualExecutionStateRepository execRepo;
    late InMemoryPlanDeclarationRepository planRepo;
    late InMemorySlaAuditLedgerRepository ledger;
    late ContractualEvaluationEngine engine;
    late TelemetryIngestionPipeline pipeline;

    const orgId = 'org-1';
    const setId = 'set-1';
    const contractId = 'c-1';
    const geoLat = -23.5505;
    const geoLng = -46.6333;

    setUp(() {
      execRepo = InMemoryContractualExecutionStateRepository();
      planRepo = InMemoryPlanDeclarationRepository();
      ledger = InMemorySlaAuditLedgerRepository();
      final statusRepo = InMemoryAssetStatusRepository();
      final traceRepo = InMemoryEvaluationTraceRepository();

      engine = ContractualEvaluationEngine(
        executionRepo: execRepo,
        planRepo: planRepo,
        ledgerRepo: ledger,
        traceRepo: traceRepo,
      );

      pipeline = TelemetryIngestionPipeline(
        engine: engine,
        assetStatusRepo: statusRepo,
      );
    });

    Future<void> seedPlan() async {
      final plan = PlanDeclaration.reconstitute(
        id: 'plan-1',
        organizationId: orgId,
        contractId: contractId,
        planVersion: 1,
        declaredAtUtc: DateTime.utc(2026, 1, 1),
        declaredByUserId: 'user-1',
        originalFileHash: 'hash-1',
        services: [],
        ruleSnapshot: const RuleSnapshot([]),
      );
      await planRepo.save(plan);
    }

    test(
      're-evaluates and compensates automatically when a latent fact arrives after a NO_SHOW sweep',
      () async {
        await seedPlan();

        // 1. Setup an obligation (SET) window: 10:00 - 11:00
        final windowStart = DateTime.utc(2026, 3, 1, 10, 0);
        final windowEnd = DateTime.utc(2026, 3, 1, 11, 0);

        final state = ContractualExecutionState.create(
          organizationId: orgId,
          setId: setId,
          contractId: contractId,
          planVersion: 1,
          startLatitude: geoLat,
          startLongitude: geoLng,
          startRadiusMeters: 100,
          contractualValue: const Money(15000),
          noShowPenaltyMultiplier: 1.5,
          windowStartUtc: windowStart,
          windowEndUtc: windowEnd,
        );
        await execRepo.save(state);

        // 2. Perform a sweep at 11:30 (obligation is PENDING, so it becomes NO_SHOW)
        final sweepTime = DateTime.utc(2026, 3, 1, 11, 30);
        await engine.sweepExpiredObligations(
          nowUtc: sweepTime,
          organizationId: orgId,
        );

        final sweptStatus = (await execRepo.findBySetId(setId))?.status;
        expect(
          sweptStatus,
          equals(ExecutionStatus.noShow),
          reason: 'SET should be marked as NO_SHOW after sweep',
        );

        // 3. Late Arrival: Facts for 10:30:00 and 10:31:00 arrive at 12:00
        final t1 = DateTime.utc(2026, 3, 1, 10, 30, 0);
        final t2 = DateTime.utc(2026, 3, 1, 10, 31, 0);

        final lateFact1 = CanonicalFact.create(
          organizationId: orgId,
          rawPayloadId: 'raw-late-1',
          assetId: 'asset-1',
          deviceId: 'DEV-1',
          sourceAdapter: 'GPS',
          receivedAtUtc: DateTime.utc(2026, 3, 1, 12, 0),
          gpsTimestamp: t1,
          lat: geoLat,
          lng: geoLng,
          speedCms: 0,
          integrityFlag: IngestionIntegrityFlag.lateArrival,
        );

        final lateFact2 = CanonicalFact.create(
          organizationId: orgId,
          rawPayloadId: 'raw-late-2',
          assetId: 'asset-1',
          deviceId: 'DEV-1',
          sourceAdapter: 'GPS',
          receivedAtUtc: DateTime.utc(2026, 3, 1, 12, 0),
          gpsTimestamp: t2,
          lat: geoLat,
          lng: geoLng,
          speedCms: 0,
          integrityFlag: IngestionIntegrityFlag.lateArrival,
        );

        // 4. Process the late facts through the pipeline
        // Pipeline sorts them, so order in list doesn't matter
        await pipeline.process([lateFact2, lateFact1], organizationId: orgId);

        // 5. Check if the status was updated (or a compensatory record created)
        final finalState = await execRepo.findBySetId(setId);

        // CHALLENGE: If the protocol is working correctly, the NO_SHOW should be resolved or countered.
        expect(
          finalState?.status,
          equals(ExecutionStatus.executed),
          reason:
              'A latent fact that arrives within the window should eventually mark the obligation as EXECUTED (INV-12)',
        );

        // Verify ledger has a "Compensatory" record or at least an EXECUTED event after the NO_SHOW.
        final entries = await ledger.getEntriesBySetId(
          setId,
          organizationId: orgId,
        );
        final eventTypes = entries.map((e) => e.type).toList();

        expect(
          eventTypes,
          contains('EXECUTION_BOUND'),
          reason:
              'Ledger must reflect that the service was actually executed later',
        );
      },
    );
  });
}
