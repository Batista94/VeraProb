import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/sla_audit/contractual_evaluation_engine.dart';
import 'package:busflow/application/sla_audit/projections/sla_execution_query_service_in_memory.dart';
import 'package:busflow/domain/entities/vehicle_operational_state.dart';
import 'package:busflow/domain/enums/connectivity_state.dart';
import 'package:busflow/domain/enums/motion_state.dart';
import 'package:busflow/domain/sla_audit/contractual_execution_state.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_evaluation_trace_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_plan_declaration_repository.dart';
import 'package:busflow/domain/sla_audit/execution_status.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_contractual_execution_state_repository.dart';
import 'package:busflow/infrastructure/sla_audit/in_memory_sla_audit_ledger_repository.dart';
import 'package:busflow/domain/sla_audit/plan_declaration.dart';
import 'package:busflow/domain/sla_audit/rule_snapshot.dart';
import 'package:busflow/domain/shared/money.dart';

void main() {
  group('Query Services Integration Consistency', () {
    test(
      'Engine -> Repo -> QueryService pipeline remains fully consistent',
      () async {
        final execRepo = InMemoryContractualExecutionStateRepository();
        final ledgerRepo = InMemorySlaAuditLedgerRepository();
        final queryService = SlaExecutionQueryServiceInMemory(repo: execRepo);

        final planRepo = InMemoryPlanDeclarationRepository();
        final engine = ContractualEvaluationEngine(
          executionRepo: execRepo,
          planRepo: planRepo,
          ledgerRepo: ledgerRepo,
          traceRepo: InMemoryEvaluationTraceRepository(),
        );

        await planRepo.save(
          PlanDeclaration.reconstitute(
            id: 'plan-xyz',
            organizationId: 'org-1',
            contractId: 'contract-x',
            planVersion: 1,
            declaredAtUtc: DateTime.utc(2026, 3, 1),
            declaredByUserId: 'test',
            originalFileHash: 'hash',
            services: const [],
            ruleSnapshot: const RuleSnapshot([]),
          ),
        );

        // 1. Setup pending state
        final windowEnd = DateTime.utc(2026, 3, 1, 7, 0);
        final state = ContractualExecutionState.create(
          organizationId: 'org-1',
          setId: 'set-consistent',
          contractId: 'contract-x',
          planVersion: 1,
          startLatitude: -23.5,
          startLongitude: -46.6,
          startRadiusMeters: 100,
          contractualValue: Money.fromDouble(200.0),
          noShowPenaltyMultiplier: 2.0, // Should be 400.0 if no-show
          windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
          windowEndUtc: windowEnd,
        );
        await execRepo.save(state);

        // Query verification (Pending)
        final initialSummary = await queryService.getSummary(
          organizationId: 'org-1',
        );
        expect(initialSummary.totalPending, 1);
        expect(initialSummary.totalExecuted, 0);
        expect(initialSummary.protectedRevenue, const Money(0));

        // 2. Execute via Engine
        final vehicle = VehicleOperationalState(
          vehicleId: 'v-100',
          tripId: 'set-consistent',
          latitude: -23.5,
          longitude: -46.6,
          smoothedSpeed: 0.0,
          motionState: MotionState.stopped,
          connectivityState: ConnectivityState.healthy,
          lastRawPingAt: DateTime.utc(2026, 3, 1, 6, 30),
          stateChangedAt: DateTime.utc(2026, 3, 1, 6, 30),
          confidence: 1.0,
          source: 'test',
        );

        final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
        final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);

        await engine.processVehicleState(vehicle, nowUtc: t0, organizationId: 'org-1');
        await engine.processVehicleState(vehicle, nowUtc: t31, organizationId: 'org-1'); // Triggers bind

        // 3. Query verification (Executed)
        final midSummary = await queryService.getSummary(
          organizationId: 'org-1',
        );
        expect(midSummary.totalPending, 0);
        expect(midSummary.totalExecuted, 1);
        expect(midSummary.protectedRevenue, const Money(20000)); // Revenue bound!
        expect(midSummary.lostRevenue, const Money(0));

        final executedList = await queryService.listByStatus(
          ExecutionStatus.executed,
          organizationId: 'org-1',
        );
        expect(executedList.first.boundVehicleId, 'v-100');

        // 4. Create another state for no-show
        final state2 = ContractualExecutionState.create(
          organizationId: 'org-1',
          setId: 'set-noshow',
          contractId: 'contract-x',
          planVersion: 1,
          startLatitude: -23.5,
          startLongitude: -46.6,
          startRadiusMeters: 100,
          contractualValue: Money.fromDouble(100.0),
          noShowPenaltyMultiplier: 1.5, // Penalty = 150.0
          windowStartUtc: DateTime.utc(2026, 3, 1, 6, 0),
          windowEndUtc: windowEnd,
        );
        await execRepo.save(state2);

        // Sweep expired via engine
        await engine.sweepExpiredObligations(
          nowUtc: DateTime.utc(2026, 3, 1, 7, 30),
          organizationId: 'org-1',
        );

        // 5. Final Query Verification
        final finalSummary = await queryService.getSummary(
          organizationId: 'org-1',
        );
        expect(finalSummary.totalPending, 0);
        expect(finalSummary.totalExecuted, 1);
        expect(finalSummary.totalNoShow, 1);
        expect(finalSummary.protectedRevenue, const Money(20000));
        expect(finalSummary.lostRevenue, const Money(15000)); // 100 * 1.5 Penalty matched

        final noshowList = await queryService.listByStatus(
          ExecutionStatus.noShow,
          organizationId: 'org-1',
        );
        expect(noshowList.first.setId, 'set-noshow');

        // Also verify ledger consistency (2 business events overall)
        expect(ledgerRepo.entries.length, 2);
      },
    );
  });
}
