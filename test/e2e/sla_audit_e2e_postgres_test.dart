import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:busflow/core/time/brazil_time.dart';
import 'package:busflow/domain/enums/motion_state.dart';
import 'package:busflow/domain/enums/connectivity_state.dart';
import 'package:busflow/domain/entities/vehicle_operational_state.dart';
import 'package:busflow/application/sla_audit/contractual_service_input.dart';
import 'package:busflow/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:busflow/application/sla_audit/declare_contractual_plan_handler.dart';
import 'package:busflow/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:busflow/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:busflow/domain/sla_audit/contractual_execution_state.dart';
import 'package:busflow/domain/sla_audit/execution_status.dart';
import 'package:busflow/infrastructure/sla_audit/postgres_plan_declaration_repository.dart';
import 'package:busflow/infrastructure/sla_audit/postgres_contractual_execution_state_repository.dart';
import 'package:busflow/infrastructure/sla_audit/postgres_sla_audit_ledger_repository.dart';
import 'package:busflow/infrastructure/sla_audit/postgres_contractual_financial_snapshot_repository.dart';
import 'package:busflow/infrastructure/sla_audit/postgres_sla_execution_query_service.dart';
import 'package:busflow/infrastructure/sla_audit/postgres_contractual_financial_impact_query_service.dart';

// ── Database Integrity Helpers ───────────────────────────

Future<void> cleanupTestData(SupabaseClient db, String cid) async {
  // Cascade guarantees cleaning plan_declarations drops
  // contractual_service_executions and execution_states + transitions.
  // However, for extra safety during test, we delete manually across roots.

  // 1. Delete Financial Snapshots
  await db
      .from('contractual_financial_snapshot')
      .delete()
      .eq('contract_id', cid);

  // 2. Delete Ledger Events
  await db.from('sla_audit_ledger').delete().eq('contract_id', cid);

  // 3. Delete Plan Declarations (Cascades to SETs and ExecStates)
  await db.from('plan_declarations').delete().eq('contract_id', cid);
}

void main() {
  // Required real credentials for the E2E test
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  const supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: '');

  late SupabaseClient client;

  // Real Postgres Repositories
  late PostgresPlanDeclarationRepository planRepo;
  late PostgresContractualExecutionStateRepository executionRepo;
  late PostgresSlaAuditLedgerRepository ledgerRepo;
  late PostgresContractualFinancialSnapshotRepository snapshotRepo;

  // Application Services
  late DeclareContractualPlanHandler declarationHandler;
  late ContractualEvaluationEngine evaluationEngine;
  late ContractualFinancialSnapshotGenerator snapshotGenerator;

  // Query Services (Projections)
  late SlaExecutionQueryServicePostgres executionQueryService;
  late ContractualFinancialImpactQueryServicePostgres impactQueryService;

  // Test Scope Constants
  final uiqueTestRunId = const Uuid().v4().substring(0, 8);
  final contractId = 'e2e-test-$uiqueTestRunId';
  final vehicleId = 'v-e2e-999';
  final planVersion = 1;

  // Temporal state
  final testBaseTimeUtc = DateTime.utc(2026, 3, 3, 10, 0); // Morning
  final operationalDateUtc = DateTime.utc(2026, 3, 3); // Normalized to 00:00Z

  String? sharedSetId;
  int? originalSnapshotLedgerEntryId;
  String? originalSnapshotId;

  // ── Setup & Teardown ─────────────────────────────────────

  setUpAll(() async {
    if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
      throw Exception(
        'E2E Test aborted: Missing SUPABASE_URL or SUPABASE_KEY. '
        'Run via: flutter test test/integration/sla_audit_e2e_postgres_test.dart '
        '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...',
      );
    }

    // Initialize the real client
    client = SupabaseClient(supabaseUrl, supabaseKey);
    BrazilTime.ensureInitialized();

    // Instantiate Data Access Layer
    planRepo = PostgresPlanDeclarationRepository(client);
    executionRepo = PostgresContractualExecutionStateRepository(client);
    ledgerRepo = PostgresSlaAuditLedgerRepository(client);
    snapshotRepo = PostgresContractualFinancialSnapshotRepository(
      client: client,
    );

    // Instantiate Application Layer
    declarationHandler = DeclareContractualPlanHandler(
      repository: planRepo,
      ledger: ledgerRepo,
    );

    evaluationEngine = ContractualEvaluationEngine(
      executionRepo: executionRepo,
      ledgerRepo: ledgerRepo,
    );

    snapshotGenerator = ContractualFinancialSnapshotGenerator(
      executionRepo: executionRepo,
      snapshotRepo: snapshotRepo,
      ledgerRepo: ledgerRepo,
    );

    executionQueryService = SlaExecutionQueryServicePostgres(client);
    impactQueryService = ContractualFinancialImpactQueryServicePostgres(client);

    // Explicit Database Cleanup Scope for this contract
    await cleanupTestData(client, contractId);
  });

  tearDownAll(() async {
    // Explicit Database Cleanup Scope
    await cleanupTestData(client, contractId);
    client.dispose();
  });

  // ── 6-Stage E2E Test Suite ───────────────────────────────

  group('SLA Audit: End-to-End Postgres Integration', () {
    test('Stage 1 — Create PlanDeclaration (Atomic Setup)', () async {
      // 1. Define Command
      final input = ContractualServiceInput(
        scheduledStartTimeUtc: testBaseTimeUtc,
        scheduledEndTimeUtc: testBaseTimeUtc.add(const Duration(minutes: 60)),
        startLatitude: -23.5505,
        startLongitude: -46.6333,
        startRadiusMeters: 100,
        endLatitude: -23.5600,
        endLongitude: -46.6400,
        endRadiusMeters: 100,
        contractualValue: 100.0,
        noShowPenaltyMultiplier: 1.5,
      );

      final command = DeclareContractualPlanCommand(
        contractId: contractId,
        declaredByUserId: 'admin-e2e',
        planVersion: planVersion,
        originalFileHash: 'e2e-hash-${DateTime.now().millisecondsSinceEpoch}',
        declaredAtUtc: testBaseTimeUtc.subtract(const Duration(days: 1)),
        services: [input],
      );

      // 2. Execute
      final plan = await declarationHandler.handle(command);
      sharedSetId = plan.services.first.setId;

      // 3. Validations
      final plans = await planRepo.findByContract(contractId);
      expect(plans.length, 1, reason: 'Exactly 1 plan in DB');

      final savedPlan = plans.first;
      expect(savedPlan.id, plan.id);
      expect(savedPlan.services.length, 1, reason: 'SET persisted via cascade');
      expect(savedPlan.services.first.setId, sharedSetId);
    });

    test('Stage 2 — Simulate Telemetry & Real-time Binding', () async {
      assert(sharedSetId != null, 'Dependency failed');

      // Given: An initial execution state
      final savedPlan = (await planRepo.findByContract(contractId)).first;
      final service = savedPlan.services.first;

      final executionState = await executionRepo.findBySetId(service.setId);
      expect(
        executionState,
        isNull,
        reason: 'State not yet created by evaluation engine sweep',
      );

      // For MVP, if external system hasn't created the state yet, the engine won't see it.
      // Wait, let's artificially initialize it as if the scheduler spawned it.
      final newState = ContractualExecutionState.create(
        setId: service.setId,
        contractId: contractId,
        planVersion: planVersion,
        startLatitude: service.startLatitude,
        startLongitude: service.startLongitude,
        startRadiusMeters: service.startRadiusMeters,
        contractualValue: service.contractualValue,
        noShowPenaltyMultiplier: service.noShowPenaltyMultiplier,
        windowStartUtc: service.scheduledStartTimeUtc.subtract(
          const Duration(minutes: 15),
        ),
        windowEndUtc: service.scheduledStartTimeUtc.add(
          const Duration(minutes: 15),
        ),
      );
      await executionRepo.save(newState);

      // Now we have 1 pending state
      final pendingStates = await executionRepo.findPendingByContractAndTime(
        contractId,
        testBaseTimeUtc,
      );
      expect(pendingStates.length, 1);

      // Simulate Telemetry exactly at Geofence Center
      final vehicleAtCenter = VehicleOperationalState(
        vehicleId: vehicleId,
        tripId: 'e2e-raw-trip', // Doesn't matter
        latitude: -23.5505,
        longitude: -46.6333,
        smoothedSpeed: 0,
        motionState: MotionState.stopped,
        connectivityState: ConnectivityState.healthy,
        lastRawPingAt: testBaseTimeUtc,
        stateChangedAt: testBaseTimeUtc,
        confidence: 1.0,
        source: 'gps',
      );

      // First tick inside geofence (Starts Dwell timer but no bind yet)
      await evaluationEngine.processVehicleState(
        vehicleAtCenter,
        nowUtc: testBaseTimeUtc,
      );

      var stateAfterTick1 = await executionRepo.findBySetId(sharedSetId!);
      expect(
        stateAfterTick1!.status.name,
        'pending',
        reason: 'Dwell time not satisfied yet',
      );

      // Second tick inside geofence 31 seconds later (Dwell time satisfied -> Bind!)
      final timeBindUtc = testBaseTimeUtc.add(const Duration(seconds: 31));
      await evaluationEngine.processVehicleState(
        vehicleAtCenter,
        nowUtc: timeBindUtc,
      );

      // Validate DB transitions
      var stateAfterTick2 = await executionRepo.findBySetId(sharedSetId!);
      expect(
        stateAfterTick2!.status.name,
        'executed',
        reason: 'Status updated to executed in DB',
      );
      expect(stateAfterTick2.boundVehicleId, vehicleId);
      expect(stateAfterTick2.bindingTimestampUtc, timeBindUtc);

      // Validate Transitions table (Raw Postgres query)
      final transitions = await client
          .from('execution_state_transitions')
          .select()
          .eq('execution_state_id', stateAfterTick2.id)
          .order('id', ascending: true);

      expect(
        transitions.length,
        greaterThanOrEqualTo(2),
        reason: 'At least 1 for creation and 1 for execute bind',
      );
      expect(transitions.last['new_status'], 'executed');
    });

    test('Stage 3 — Validate SLA Audit Ledger Constraints', () async {
      assert(sharedSetId != null, 'Dependency failed');

      // Get all ledger events for this contract
      final entries =
          await client
                  .from('sla_audit_ledger')
                  .select()
                  .eq('contract_id', contractId)
                  .order('id', ascending: true)
              as List;

      expect(
        entries.length,
        2,
        reason: '1 PLAN_DECLARED + 1 EXECUTION_BOUND expected',
      );

      int previousId = -1;
      bool foundPlanDeclared = false;
      bool foundExecutionBound = false;

      for (var row in entries) {
        final currentId = row['id'] as int;
        expect(
          currentId,
          greaterThan(previousId),
          reason: 'IDs must be strictly monotonic',
        );
        previousId = currentId;

        final type = row['type'];
        if (type == 'PLAN_DECLARED') foundPlanDeclared = true;
        if (type == 'EXECUTION_BOUND') foundExecutionBound = true;

        expect(row['contract_id'], contractId);
        expect(row['payload'], isNotNull);
      }

      expect(foundPlanDeclared, isTrue);
      expect(foundExecutionBound, isTrue);

      // Verify Repo abstraction works too
      final lastId = await ledgerRepo.getLastEntryId();
      expect(lastId, entries.last['id']);
      originalSnapshotLedgerEntryId = lastId;
    });

    test('Stage 4 — Generate Financial Snapshot', () async {
      assert(originalSnapshotLedgerEntryId != null, 'Dependency failed');

      // Run daily closure manually for the test date
      await snapshotGenerator.generateDailySnapshot(
        operationalDateUtc,
        contractId: contractId,
      );

      // Check repo
      final snapshots = await snapshotRepo.findAll(contractId: contractId);
      expect(snapshots.length, 1, reason: 'Exactly 1 active snapshot created');

      final snap = snapshots.first;
      originalSnapshotId = snap.id;

      expect(snap.operationalDateUtc, operationalDateUtc);
      expect(
        snap.totalContractedRevenue.cents,
        10000,
        reason: '100 BRL = 10000 cents',
      );
      expect(
        snap.protectedRevenue.cents,
        10000,
        reason: '1 executed SET = 100% protected',
      );
      expect(snap.revenueAtRisk.cents, 0);
      expect(snap.lostRevenue.cents, 0);
      expect(snap.lastLedgerEntryId, originalSnapshotLedgerEntryId);
      expect(snap.previousSnapshotId, isNull);
    });

    test('Stage 5 — Snapshot Chain Reprocessing', () async {
      assert(originalSnapshotId != null, 'Dependency failed');

      // Reprocess explicitly
      await snapshotGenerator.reprocessDailySnapshot(
        operationalDateUtc,
        contractId: contractId,
        previousSnapshotId: originalSnapshotId!,
        reprocessingReason: 'E2E Testing Chain Continuity',
        authorUserId: 'admin-e2e',
      );

      // Repo should STILL only return 1 active snapshot
      final activeSnapshots = await snapshotRepo.findAll(
        contractId: contractId,
      );
      expect(
        activeSnapshots.length,
        1,
        reason: 'findAll() filters superseded snapshots',
      );

      final activeSnap = activeSnapshots.first;
      expect(
        activeSnap.id,
        isNot(originalSnapshotId),
        reason: 'A new UUID was generated',
      );
      expect(
        activeSnap.previousSnapshotId,
        originalSnapshotId,
        reason: 'Causality link maintained',
      );
      expect(activeSnap.reprocessingReason, 'E2E Testing Chain Continuity');

      // But the database must contain exactly 2 rows
      final rawCount = await client
          .from('contractual_financial_snapshot')
          .select('id')
          .eq('contract_id', contractId)
          .count(CountOption.exact);

      expect(
        rawCount.count,
        2,
        reason: 'No DELETE occurred, the snapshot was superseded cleanly',
      );
    });

    test('Stage 6 — Immutability Interface Constraints', () async {
      // Interfaces in Dart enforce the available methods.
      // The Postgres repositories implement the Domain interfaces which intentionally lack update/delete.

      // 3. Aggregate internal immutability / duplicate check
      final duplicatePlanCommand = DeclareContractualPlanCommand(
        contractId: contractId, // same contract
        planVersion: planVersion, // same version
        declaredByUserId: 'hacker',
        originalFileHash: 'fake',
        declaredAtUtc: DateTime.utc(2026, 3, 3),
        services: [
          ContractualServiceInput(
            scheduledStartTimeUtc: testBaseTimeUtc,
            scheduledEndTimeUtc: testBaseTimeUtc.add(const Duration(hours: 1)),
            startLatitude: 0,
            startLongitude: 0,
            startRadiusMeters: 10,
            endLatitude: 0,
            endLongitude: 0,
            endRadiusMeters: 10,
            contractualValue: 1,
            noShowPenaltyMultiplier: 1.0,
          ),
        ],
      );

      // Should fail either in DB constraint or domain layer
      expect(
        () async => await declarationHandler.handle(duplicatePlanCommand),
        throwsException,
        reason:
            'Postgres UNIQUE(contract_id, plan_version) must reject this insert',
      );
    });

    test('Stage 7 — E2E UI Dashboard Query Coverage', () async {
      // 1. Verify SLA Execution Item projections
      final summary = await executionQueryService.getSummary(
        contractId: contractId,
      );

      expect(summary.totalExecuted, 1, reason: '1 executed set from telemetry');
      expect(summary.totalPending, 0);
      expect(summary.total, 1);
      expect(summary.protectedRevenue, 100.0);

      final executedList = await executionQueryService.listByStatus(
        ExecutionStatus.executed,
        contractId: contractId,
      );
      expect(executedList.first.boundVehicleId, vehicleId);

      // 2. Verify Financial Impact projections
      final impact = await impactQueryService.getImpact(contractId: contractId);

      expect(
        impact.protectedRevenue.cents,
        10000,
        reason: '100 BRL = 10000 cents',
      );
      expect(impact.lostRevenue.cents, 0);
      expect(impact.revenueAtRisk.cents, 0);
    });
  });
}
