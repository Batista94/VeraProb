import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/evidence_payload.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';

import '_engine_test_helpers.dart';

/// Helper for capping/audit tests — returns trace after bind commit.
Future<EvaluationTrace> processAndGetTrace({
  required dynamic deps, // ignore: inference_failure_on_untyped_parameter
  int toleranceMinutes = 0,
  int penaltyPerMinuteCents = 200,
  int? maxPenaltyCapCents,
  required int delayMinutes,
}) async {
  await seedPlanWithDelayRule(
    deps.planRepo as InMemoryPlanDeclarationRepository,
    'c-1',
    1,
    toleranceMinutes: toleranceMinutes,
    penaltyPerMinuteCents: penaltyPerMinuteCents,
    maxPenaltyCapCents: maxPenaltyCapCents,
  );

  final windowStart = nowUtc.subtract(Duration(minutes: delayMinutes));
  final state = makeExecState(
    contractId: 'c-1',
    windowStart: windowStart,
    windowEnd: nowUtc.add(const Duration(hours: 1)),
  );
  await (deps.repo as InMemoryContractualExecutionStateRepository).save(state);

  // First ping: enters geofence (starts dwell tracking)
  await (deps.engine as ContractualEvaluationEngine).processVehicleState(
    makeVehicleState(),
    nowUtc: windowStart,
    organizationId: 'org-1',
  );

  // Second ping: satisfies dwell → triggers commit with delay decision
  await (deps.engine as ContractualEvaluationEngine).processVehicleState(
    makeVehicleState(),
    nowUtc: nowUtc,
    organizationId: 'org-1',
  );

  final traces = await (deps.traceRepo as InMemoryEvaluationTraceRepository)
      .findByEntityId(state.setId);
  expect(traces, isNotEmpty, reason: 'Expected trace after commit');
  return traces.first;
}

/// Helper for grace period tests (no DELAY decision expected).
Future<EvaluationTrace> processAndGetTraceForGrace({
  required dynamic deps, // ignore: inference_failure_on_untyped_parameter
  required int toleranceMinutes,
  required int delayMinutes,
}) async {
  await seedPlanWithDelayRule(
    deps.planRepo as InMemoryPlanDeclarationRepository,
    'c-1',
    1,
    toleranceMinutes: toleranceMinutes,
    penaltyPerMinuteCents: 200,
  );

  final windowStart = nowUtc.subtract(Duration(minutes: delayMinutes));
  final state = makeExecState(
    contractId: 'c-1',
    windowStart: windowStart,
    windowEnd: nowUtc.add(const Duration(hours: 1)),
  );
  await (deps.repo as InMemoryContractualExecutionStateRepository).save(state);

  // First ping: enters geofence
  await (deps.engine as ContractualEvaluationEngine).processVehicleState(
    makeVehicleState(),
    nowUtc: windowStart,
    organizationId: 'org-1',
  );

  // Second ping: satisfies dwell → triggers commit
  await (deps.engine as ContractualEvaluationEngine).processVehicleState(
    makeVehicleState(),
    nowUtc: nowUtc,
    organizationId: 'org-1',
  );

  final traces = await (deps.traceRepo as InMemoryEvaluationTraceRepository)
      .findByEntityId(state.setId);
  expect(traces, isNotEmpty, reason: 'Expected trace after commit');
  return traces.first;
}

void main() {
  group('ContractualEvaluationEngine — Orchestration Rules', () {
    group('INV-15: Maintenance Inhibition', () {
      test(
        'vehicle in maintenance → zero financial impact in ledger',
        () async {
          final deps = createEngineWithAssetStatus();

          await deps.assetStatusRepo.append(
            AssetStatusEvent.create(
              organizationId: 'org-1',
              assetId: 'v-1',
              newStatus: AssetStatus.maintenance,
              previousStatus: AssetStatus.active,
              occurredAtUtc: nowUtc.subtract(const Duration(hours: 1)),
              triggeredBy: 'test',
            ),
          );

          await seedPlan(deps.planRepo, 'c-1', 1);
          final state = makeExecState(
            contractId: 'c-1',
            windowStart: nowUtc.subtract(const Duration(minutes: 30)),
            windowEnd: nowUtc.add(const Duration(hours: 1)),
          );
          await deps.repo.save(state);

          await deps.engine.processVehicleState(
            makeVehicleState(vehicleId: 'v-1'),
            nowUtc: nowUtc,
            organizationId: 'org-1',
          );

          final entries = deps.ledger.entries;
          expect(entries, hasLength(1));
          expect(entries.first.type, 'MAINTENANCE_INHIBITED');
          expect(
            entries.first.payload['inhibition_reason'],
            'MAINTENANCE_INHIBITION',
          );
          expect(
            entries.first.payload['vehicle_status_at_evaluation'],
            'maintenance',
          );
          // Legibilidade humana — campo obrigatório para suporte
          expect(
            entries.first.payload['vehicle_status_at_evaluation'],
            isNotNull,
          );
          expect(
            entries.first.payload['vehicle_status_at_evaluation'],
            isA<String>(),
          );
          expect(
            entries.first.payload['vehicle_status_at_evaluation'],
            isNot(matches(r'^\d+$')),
          );
        },
      );

      test('ledger emits MAINTENANCE_INHIBITED entry type', () async {
        final deps = createEngineWithAssetStatus();

        await deps.assetStatusRepo.append(
          AssetStatusEvent.create(
            organizationId: 'org-1',
            assetId: 'v-1',
            newStatus: AssetStatus.maintenance,
            previousStatus: AssetStatus.active,
            occurredAtUtc: nowUtc.subtract(const Duration(hours: 2)),
            triggeredBy: 'test',
          ),
        );

        await seedPlan(deps.planRepo, 'c-1', 1);
        final state = makeExecState(
          contractId: 'c-1',
          windowStart: nowUtc.subtract(const Duration(minutes: 30)),
          windowEnd: nowUtc.add(const Duration(hours: 1)),
        );
        await deps.repo.save(state);

        await deps.engine.processVehicleState(
          makeVehicleState(),
          nowUtc: nowUtc,
          organizationId: 'org-1',
        );

        final entries = deps.ledger.entries;
        expect(entries, hasLength(1));
        expect(entries.first.type, 'MAINTENANCE_INHIBITED');
      });

      test('MAINTENANCE_INHIBITED payload contains '
          'inhibition_reason: MAINTENANCE_INHIBITION', () async {
        final deps = createEngineWithAssetStatus();

        await deps.assetStatusRepo.append(
          AssetStatusEvent.create(
            organizationId: 'org-1',
            assetId: 'v-1',
            newStatus: AssetStatus.offDuty,
            previousStatus: AssetStatus.active,
            occurredAtUtc: nowUtc.subtract(const Duration(hours: 3)),
            triggeredBy: 'test',
          ),
        );

        await seedPlan(deps.planRepo, 'c-1', 1);
        final state = makeExecState(
          contractId: 'c-1',
          windowStart: nowUtc.subtract(const Duration(minutes: 30)),
          windowEnd: nowUtc.add(const Duration(hours: 1)),
        );
        await deps.repo.save(state);

        await deps.engine.processVehicleState(
          makeVehicleState(),
          nowUtc: nowUtc,
          organizationId: 'org-1',
        );

        final entries = deps.ledger.entries;
        expect(entries, hasLength(1));
        expect(
          entries.first.payload['inhibition_reason'],
          'MAINTENANCE_INHIBITION',
        );
        expect(
          entries.first.payload['vehicle_status_at_evaluation'],
          'offDuty',
        );
      });

      test('vehicle returning to active is evaluated normally', () async {
        final deps = createEngineWithAssetStatus();

        // Vehicle was in maintenance, then returned to active
        await deps.assetStatusRepo.append(
          AssetStatusEvent.create(
            organizationId: 'org-1',
            assetId: 'v-1',
            newStatus: AssetStatus.maintenance,
            previousStatus: AssetStatus.active,
            occurredAtUtc: nowUtc.subtract(const Duration(hours: 5)),
            triggeredBy: 'test',
          ),
        );
        await deps.assetStatusRepo.append(
          AssetStatusEvent.create(
            organizationId: 'org-1',
            assetId: 'v-1',
            newStatus: AssetStatus.active,
            previousStatus: AssetStatus.maintenance,
            occurredAtUtc: nowUtc.subtract(const Duration(hours: 1)),
            triggeredBy: 'test',
          ),
        );

        await seedPlanWithDwellRule(deps.planRepo, 'c-1', 1);
        final state = makeExecState(
          contractId: 'c-1',
          windowStart: nowUtc.subtract(const Duration(minutes: 30)),
          windowEnd: nowUtc.add(const Duration(hours: 1)),
        );
        await deps.repo.save(state);

        await deps.engine.processVehicleState(
          makeVehicleState(),
          nowUtc: nowUtc,
          organizationId: 'org-1',
        );

        // Should NOT have MAINTENANCE_INHIBITED entry
        final hasInhibition = deps.ledger.entries.any(
          (e) => e.type == 'MAINTENANCE_INHIBITED',
        );
        expect(hasInhibition, isFalse);
      });
    });

    group('Penalty Capping (max_penalty_cap_cents)', () {
      test('penalty above cap is truncated to cap — not dropped', () async {
        final deps = createEngine();
        final trace = await processAndGetTrace(
          deps: deps,
          toleranceMinutes: 0,
          penaltyPerMinuteCents: 200,
          maxPenaltyCapCents: 500,
          delayMinutes: 10,
        );

        final delayDecision = trace.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;
        expect(evidence.grossPenaltyCents, 2000); // 10 min × 200 cents
        expect(evidence.finalPenaltyCents, 500); // capped
        expect(evidence.capApplied, isTrue);
      });

      test('penalty below cap is unchanged', () async {
        final deps = createEngine();
        final trace = await processAndGetTrace(
          deps: deps,
          toleranceMinutes: 0,
          penaltyPerMinuteCents: 100,
          maxPenaltyCapCents: 5000,
          delayMinutes: 10,
        );

        final delayDecision = trace.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;
        expect(evidence.grossPenaltyCents, 1000); // 10 min × 100 cents
        expect(evidence.finalPenaltyCents, 1000); // unchanged
        expect(evidence.capApplied, isFalse);
      });

      test('DelayPenaltyEvidence.capApplied is true when truncated', () async {
        final deps = createEngine();
        final trace = await processAndGetTrace(
          deps: deps,
          toleranceMinutes: 0,
          penaltyPerMinuteCents: 500,
          maxPenaltyCapCents: 1000,
          delayMinutes: 5,
        );

        final delayDecision = trace.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;
        // gross = 5 × 500 = 2500, cap = 1000
        expect(evidence.capApplied, isTrue);
      });

      test(
        'grossPenaltyCents and finalPenaltyCents differ when cap applies',
        () async {
          final deps = createEngine();
          final trace = await processAndGetTrace(
            deps: deps,
            toleranceMinutes: 0,
            penaltyPerMinuteCents: 300,
            maxPenaltyCapCents: 600,
            delayMinutes: 5,
          );

          final delayDecision = trace.decisions.firstWhere(
            (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
          );
          final evidence = delayDecision.evidence as DelayPenaltyEvidence;
          // gross = 5 × 300 = 1500, cap = 600
          expect(evidence.grossPenaltyCents, 1500);
          expect(evidence.finalPenaltyCents, 600);
          expect(
            evidence.grossPenaltyCents,
            isNot(equals(evidence.finalPenaltyCents)),
          );
        },
      );
    });

    group('Grace Period (delayToleranceMinutes)', () {
      test('delay within tolerance → billableMinutes = 0, '
          'no financial impact', () async {
        final deps = createEngine();
        final trace = await processAndGetTraceForGrace(
          deps: deps,
          toleranceMinutes: 10,
          delayMinutes: 5,
        );

        final hasDelayDecision = trace.decisions.any(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
        );
        expect(hasDelayDecision, isFalse);
      });

      test(
        'delay at exactly tolerance boundary → no financial impact',
        () async {
          final deps = createEngine();
          final trace = await processAndGetTraceForGrace(
            deps: deps,
            toleranceMinutes: 10,
            delayMinutes: 10,
          );

          final hasDelayDecision = trace.decisions.any(
            (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
          );
          expect(hasDelayDecision, isFalse);
        },
      );

      test('t+1: first billable minute triggers charge — '
          'off-by-one frontier', () async {
        final deps = createEngine();

        // tolerance = 10, delay = 11 → billableMinutes = 1
        final trace = await processAndGetTrace(
          deps: deps,
          toleranceMinutes: 10,
          penaltyPerMinuteCents: 200,
          delayMinutes: 11,
        );

        final delayDecision = trace.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;
        expect(evidence.delayMinutes, 11);
        expect(evidence.toleranceMinutes, 10);
        expect(evidence.billableMinutes, 1); // 11 - 10 = 1
        expect(evidence.grossPenaltyCents, 200); // 1 × 200
        expect(evidence.finalPenaltyCents, 200);
        expect(evidence.capApplied, isFalse);
      });

      test('delay beyond tolerance charges only '
          'excess minutes × penaltyPerMinute', () async {
        final deps = createEngine();
        final trace = await processAndGetTrace(
          deps: deps,
          toleranceMinutes: 5,
          penaltyPerMinuteCents: 200,
          delayMinutes: 15,
        );

        final delayDecision = trace.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;
        expect(evidence.delayMinutes, 15);
        expect(evidence.toleranceMinutes, 5);
        expect(evidence.billableMinutes, 10);
        expect(evidence.grossPenaltyCents, 2000); // 10 × 200
        expect(evidence.finalPenaltyCents, 2000); // no cap
        expect(evidence.capApplied, isFalse);
      });
    });

    group('Audit Trail Completeness', () {
      test('DelayPenaltyEvidence contains all required fields', () async {
        final deps = createEngine();
        final trace = await processAndGetTrace(
          deps: deps,
          toleranceMinutes: 0,
          penaltyPerMinuteCents: 100,
          maxPenaltyCapCents: 500,
          delayMinutes: 10,
        );

        final delayDecision = trace.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;

        expect(evidence.delayMinutes, isA<int>());
        expect(evidence.toleranceMinutes, isA<int>());
        expect(evidence.billableMinutes, isA<int>());
        expect(evidence.grossPenaltyCents, isA<int>());
        expect(evidence.finalPenaltyCents, isA<int>());
        expect(evidence.capApplied, isA<bool>());

        // Serialization round-trip
        final json = evidence.toJson();
        expect(json['_type'], 'delay_penalty');
        expect(json['delay_minutes'], evidence.delayMinutes);
        expect(json['tolerance_minutes'], evidence.toleranceMinutes);
        expect(json['billable_minutes'], evidence.billableMinutes);
        expect(json['gross_penalty_cents'], evidence.grossPenaltyCents);
        expect(json['final_penalty_cents'], evidence.finalPenaltyCents);
        expect(json['cap_applied'], evidence.capApplied);
      });

      test('MaintenanceInhibitionEvidence contains '
          'vehicleStatusAtEvaluation', () async {
        final deps = createEngineWithAssetStatus();

        await deps.assetStatusRepo.append(
          AssetStatusEvent.create(
            organizationId: 'org-1',
            assetId: 'v-1',
            newStatus: AssetStatus.maintenance,
            previousStatus: AssetStatus.active,
            occurredAtUtc: nowUtc.subtract(const Duration(hours: 1)),
            triggeredBy: 'test',
          ),
        );

        await seedPlan(deps.planRepo, 'c-1', 1);
        final state = makeExecState(
          contractId: 'c-1',
          windowStart: nowUtc.subtract(const Duration(minutes: 30)),
          windowEnd: nowUtc.add(const Duration(hours: 1)),
        );
        await deps.repo.save(state);

        await deps.engine.processVehicleState(
          makeVehicleState(),
          nowUtc: nowUtc,
          organizationId: 'org-1',
        );

        final entries = deps.ledger.entries;
        expect(entries, isNotEmpty, reason: 'Expected at least one entry');
        final payload = entries.first.payload;

        expect(payload['vehicle_status_at_evaluation'], 'maintenance');
        expect(payload['inhibition_reason'], 'MAINTENANCE_INHIBITION');

        // Deserialization round-trip
        final evidence = MaintenanceInhibitionEvidence.fromJson(payload);
        expect(evidence.vehicleStatusAtEvaluation, 'maintenance');
        expect(evidence.inhibitionReason, 'MAINTENANCE_INHIBITION');
      });
    });
  });
}
