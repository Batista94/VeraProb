import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/domain/sla_audit/contract_repository.dart';
import 'package:veraprob/domain/sla_audit/contract_status.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'package:veraprob/domain/sla_audit/rule_snapshot.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule_repository.dart';
import 'package:veraprob/core/time/brazil_time.dart';
import 'package:veraprob/domain/enums/motion_state.dart';
import 'package:veraprob/domain/enums/connectivity_state.dart';
import 'package:veraprob/domain/entities/vehicle_operational_state.dart';
import 'package:veraprob/application/sla_audit/contractual_service_input.dart';
import 'package:veraprob/application/sla_audit/declare_contractual_plan_command.dart';
import 'package:veraprob/application/sla_audit/declare_contractual_plan_handler.dart';
import 'package:veraprob/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:veraprob/application/sla_audit/projections/contractual_financial_snapshot_generator.dart';
import 'package:veraprob/domain/sla_audit/contractual_execution_state.dart';
import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/sla_audit/plan_declaration.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_plan_declaration_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_execution_state_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_audit_ledger_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_financial_snapshot_repository.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_sla_execution_query_service.dart';
import 'package:veraprob/infrastructure/sla_audit/postgres_contractual_financial_impact_query_service.dart';
import 'package:veraprob/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/infrastructure/admin/in_memory_active_vehicle_repository.dart';

// ── Database Integrity Helpers ───────────────────────────

Future<void> cleanupTestData(SupabaseClient db, String cid) async {
  // Cloud Validation Environment:
  // DELETE operations are prohibited by architecture hardening.
  // Tests rely on unique contract IDs instead of teardown logic.
}

void main() {
  // Required real credentials for the E2E test.
  // Inject via: flutter test --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
  // When credentials are absent the entire suite is skipped cleanly instead of
  // failing in setUpAll, which produces misleading error noise in CI.
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  const supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: '');

  if (supabaseUrl.isEmpty || supabaseKey.isEmpty) {
    // Register a single skipped placeholder so the runner reports this file
    // as skipped rather than errored, keeping the CI signal clean.
    test(
      'SLA Audit E2E (skipped — no Supabase credentials)',
      () {},
      skip:
          'Set SUPABASE_URL and SUPABASE_KEY via --dart-define to run E2E tests.',
    );
    return;
  }

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
  const vehicleId = 'v-e2e-999';
  const planVersion = 1;

  // Temporal state
  final testBaseTimeUtc = DateTime.utc(2026, 3, 3, 10, 0); // Morning
  final operationalDateUtc = DateTime.utc(2026, 3, 3); // Normalized to 00:00Z

  String? sharedSetId;
  String? originalSnapshotLedgerEntryId;
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
      ruleRepository: MockContractualRuleRepository(),
      contractRepository: MockContractRepository(),
      zoneRepository: _StubZoneRepository(),
      vehicleRepository: const InMemoryActiveVehicleRepository(
        countsByOrg: {'00000000-0000-0000-0000-000000000001': 1},
      ),
    );

    evaluationEngine = ContractualEvaluationEngine(
      executionRepo: executionRepo,
      planRepo: planRepo,
      ledgerRepo: ledgerRepo,
      traceRepo: InMemoryEvaluationTraceRepository(),
    );

    snapshotGenerator = ContractualFinancialSnapshotGenerator(
      executionRepo: executionRepo,
      snapshotRepo: snapshotRepo,
      ledgerRepo: ledgerRepo,
    );

    executionQueryService = SlaExecutionQueryServicePostgres(client);
    impactQueryService = ContractualFinancialImpactQueryServicePostgres(client);
  });

  tearDownAll(() async {
    await client.dispose();
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
        organizationId: '00000000-0000-0000-0000-000000000001',
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
      final plans = await planRepo.findByContract(
        contractId,
        organizationId: '00000000-0000-0000-0000-000000000001',
      );
      expect(plans.length, 1, reason: 'Exactly 1 plan in DB');

      final savedPlan = plans.first;
      expect(savedPlan.id, plan.id);
      expect(savedPlan.services.length, 1, reason: 'SET persisted via cascade');
      expect(savedPlan.services.first.setId, sharedSetId);
    });

    test('Stage 2 — Simulate Telemetry & Real-time Binding', () async {
      assert(sharedSetId != null, 'Dependency failed');

      // Given: An initial execution state
      final savedPlan = (await planRepo.findByContract(
        contractId,
        organizationId: '00000000-0000-0000-0000-000000000001',
      )).first;
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
        organizationId: '00000000-0000-0000-0000-000000000001',
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
        organizationId: '00000000-0000-0000-0000-000000000001',
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
        organizationId: '00000000-0000-0000-0000-000000000001',
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
        organizationId: '00000000-0000-0000-0000-000000000001',
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
        '00000000-0000-0000-0000-000000000001',
        operationalDateUtc,
        contractId: contractId,
      );

      // Check repo
      final snapshots = await snapshotRepo.findAll(
        organizationId: '00000000-0000-0000-0000-000000000001',
        contractId: contractId,
      );
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
        '00000000-0000-0000-0000-000000000001',
        operationalDateUtc,
        contractId: contractId,
        previousSnapshotId: originalSnapshotId!,
        reprocessingReason: 'E2E Testing Chain Continuity',
        authorUserId: 'admin-e2e',
      );

      // Repo should STILL only return 1 active snapshot
      final activeSnapshots = await snapshotRepo.findAll(
        organizationId: '00000000-0000-0000-0000-000000000001',
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

    test('Stage 6 — Postgres Idempotency (Unique Constraint)', () async {
      // Let's test idempotency by attempting a raw insert of a duplicate SET.
      final duplicateSet = ContractualExecutionState.create(
        organizationId: '00000000-0000-0000-0000-000000000001',
        setId: sharedSetId!, // The SAME set ID
        contractId: contractId,
        planVersion: planVersion,
        startLatitude: -23.5505,
        startLongitude: -46.6333,
        startRadiusMeters: 100,
        contractualValue: const Money(10000),
        noShowPenaltyMultiplier: 1.5,
        windowStartUtc: testBaseTimeUtc,
        windowEndUtc: testBaseTimeUtc,
      );

      // This MUST throw a PostgrestException (code 23505 - unique_violation)
      expect(
        () async => await executionRepo.save(duplicateSet),
        throwsA(isA<PostgrestException>()),
        reason:
            'Postgres UNIQUE(set_id) or (plan,shift,date) must reject duplicate insertions',
      );
    });

    test('Stage 7 — Postgres RLS Isolation (Multi-Tenant Penetration)', () async {
      // Simulate an Operator from '00000000-0000-0000-0000-000000000002' trying to read '00000000-0000-0000-0000-000000000001' data via API.
      // In a real environment with JWTs, Supabase Auth enforces this automatically.
      // Since our integration tests use the service_role key or bypass Auth,
      // the Application logic MUST enforce isolation via `organizationId` parameter.

      // 1. Try to read the contract plans using a different Org ID
      final stolenPlans = await planRepo.findByContract(
        contractId,
        organizationId: '00000000-0000-0000-0000-000000000002',
      );
      expect(
        stolenPlans,
        isEmpty,
        reason: 'RLS/Application boundary must isolate tenants',
      );

      // 2. Try to query the execution states
      final stolenExecutions = await executionQueryService.listByStatus(
        ExecutionStatus.executed,
        organizationId: '00000000-0000-0000-0000-000000000002',
        contractId: contractId,
      );
      expect(
        stolenExecutions,
        isEmpty,
        reason: 'Cross-tenant execution queries must return 0 rows',
      );

      // 3. Try to generate a snapshot for another org's contract
      await snapshotGenerator.generateDailySnapshot(
        '00000000-0000-0000-0000-000000000002', // Attack vector
        operationalDateUtc,
        contractId: contractId,
      );

      final stolenSnapshots = await snapshotRepo.findAll(
        organizationId: '00000000-0000-0000-0000-000000000002',
        contractId: contractId,
      );
      expect(
        stolenSnapshots,
        isEmpty,
        reason: 'Cannot generate or read snapshots across tenant boundaries',
      );
    });

    test('Stage 7.1 — Postgres RLS Active Attack (Write Sabotage)', () async {
      // Setup: Create a legitimate plan for org-1
      final hackerPlanId = const Uuid().v4();

      // Attempt 1: Hacker tries to 'overwrite' org-1's plan data by injecting their orgId
      // In a hardened system, if the JWT is org-hacker, Postgres RLS 'WITH CHECK'
      // will reject an INSERT/UPDATE where organization_id != auth.jwt().
      // Here we simulate the repo call.

      final forgedPlan = PlanDeclaration.reconstitute(
        id: hackerPlanId,
        organizationId:
            '00000000-0000-0000-0000-000000000001', // Targeting Org 1
        contractId: contractId,
        planVersion: 99,
        declaredByUserId: 'hacker',
        originalFileHash: 'forged',
        declaredAtUtc: DateTime.now().toUtc(),
        ruleSnapshot: const RuleSnapshot([]),
        services: [],
      );

      // This should fail at the Postgres level if RLS is enforced on the service_role
      // or if the application layer validates the command org vs repo org.
      // Since integration tests often use service_role, we focus on the REPO and DB level.

      // If we use a client restricted by RLS (authenticated as hacker):
      // final hackerClient = SupabaseClient(url, hackerJwt);
      // final hackerRepo = PostgresPlanDeclarationRepository(hackerClient);

      // Attempt: Sabotage Org 1's plan data
      // This should be blocked by RLS if using a restricted client.
      // Even with service_role, our repositories should enforce org isolation.
      expect(
        () async => await planRepo.save(forgedPlan),
        throwsA(isA<PostgrestException>()),
        reason:
            'RLS WITH CHECK must prevent inserting data for a different organization_id',
      );

      final leakyData = await planRepo.findByContract(
        contractId,
        organizationId: '00000000-0000-0000-0000-000000000002',
      );
      expect(leakyData, isEmpty);
    });

    test('Stage 8 — E2E UI Dashboard Query Coverage', () async {
      // 1. Verify SLA Execution Item projections
      final summary = await executionQueryService.getSummary(
        organizationId: '00000000-0000-0000-0000-000000000001',
        contractId: contractId,
      );

      expect(summary.totalExecuted, 1, reason: '1 executed set from telemetry');
      expect(summary.totalPending, 0);
      expect(summary.total, 1);
      expect(summary.protectedRevenue, const Money(10000));

      final executedList = await executionQueryService.listByStatus(
        ExecutionStatus.executed,
        organizationId: '00000000-0000-0000-0000-000000000001',
        contractId: contractId,
      );
      expect(executedList.first.boundVehicleId, vehicleId);

      // 2. Verify Financial Impact projections
      final impact = await impactQueryService.getImpact(
        organizationId: '00000000-0000-0000-0000-000000000001',
        contractId: contractId,
      );

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

class MockContractualRuleRepository implements ContractualRuleRepository {
  @override
  Future<RuleSnapshot> getActiveSnapshotForContract(
    String orgId,
    String contractId,
  ) async {
    return const RuleSnapshot([]);
  }

  @override
  Future<void> saveRule(ContractualRule rule) async {}
}

/// Returns a draft [Contract] for any non-empty contractId.
/// Allows the handler to validate and activate contracts during E2E tests.
class MockContractRepository implements ContractRepository {
  @override
  Future<Contract?> findById(
    String id, {
    required String organizationId,
  }) async {
    if (id.isEmpty) return null;
    return Contract.reconstitute(
      id: id,
      organizationId: organizationId,
      name: 'E2E Test Contract',
      contractorName: 'E2E Contractor',
      validFromUtc: DateTime.utc(2026, 1, 1),
      validUntilUtc: DateTime.utc(2026, 12, 31),
      status: ContractStatus.draft,
      createdAtUtc: DateTime.utc(2026, 1, 1),
    );
  }

  @override
  Future<void> save(Contract contract) async {}

  @override
  Future<List<Contract>> findByOrganization(
    String organizationId, {
    ContractStatus? status,
  }) async {
    return [];
  }
}

class _StubZoneRepository implements OperationalZoneRepository {
  @override
  Future<List<OperationalZone>> findByOrganization(
    String organizationId,
  ) async => [
    OperationalZone.create(
      organizationId: organizationId,
      name: 'Stub',
      type: ZoneType.garagem,
    ),
  ];

  @override
  Future<OperationalZone?> findById(
    String id, {
    required String organizationId,
  }) async => null;

  @override
  Future<void> save(OperationalZone zone) async {}
}
