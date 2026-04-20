import 'package:flutter_test/flutter_test.dart';

import '_engine_test_helpers.dart';

void main() {
  setUpAll(() {
    initializeTimezones();
  });

  late InMemoryContractualExecutionStateRepository repo;
  late InMemoryPlanDeclarationRepository planRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late ContractualEvaluationEngine engine;

  setUp(() {
    final deps = createEngine();
    repo = deps.repo;
    planRepo = deps.planRepo;
    ledger = deps.ledger;
    engine = deps.engine;
  });

  group('ContractualEvaluationEngine — Penalty & SLA Evaluation', () {
    // ── 7.5: Grace Period ─────────────────────────────────────

    group('gracePeriodMinutes (7.5)', () {
      test('SET inside grace period is skipped — no binding occurs', () async {
        // windowStart = 06:00. Grace period = 10 min. Telemetry arrives at 06:05.
        const contractId = 'c-grace';
        final windowStart = DateTime.utc(2026, 3, 1, 6, 0);
        await seedPlanWithGracePeriod(planRepo, contractId, 1, 10);

        final state = makeExecState(
          contractId: contractId,
          windowStart: windowStart,
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        );
        await repo.save(state);

        // Telemetry inside geofence, but within grace window (06:05 < 06:00 + 10min)
        final duringGrace = DateTime.utc(2026, 3, 1, 6, 5);
        await engine.processVehicleState(
          makeVehicleState(),
          nowUtc: duringGrace,
          organizationId: 'org-1',
        );

        final s = await repo.findBySetId(state.setId);
        expect(
          s!.status,
          ExecutionStatus.pending,
          reason: 'SET should remain pending during grace period',
        );
        expect(ledger.entries, isEmpty);
      });

      test(
        'SET after grace period is evaluated — binding occurs normally',
        () async {
          // windowStart = 06:00. Grace period = 5 min. Telemetry arrives after 06:05.
          const contractId = 'c-after-grace';
          final windowStart = DateTime.utc(2026, 3, 1, 6, 0);
          await seedPlanWithGracePeriod(planRepo, contractId, 1, 5);

          final state = makeExecState(
            contractId: contractId,
            windowStart: windowStart,
            windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
          );
          await repo.save(state);

          // t0: first ping after grace ends — 06:06
          final afterGrace = DateTime.utc(2026, 3, 1, 6, 6, 0);
          await engine.processVehicleState(
            makeVehicleState(),
            nowUtc: afterGrace,
            organizationId: 'org-1',
          );

          // t31: 31s later — dwell satisfied, binding should occur
          final t31 = DateTime.utc(2026, 3, 1, 6, 6, 31);
          await engine.processVehicleState(
            makeVehicleState(),
            nowUtc: t31,
            organizationId: 'org-1',
          );

          final s = await repo.findBySetId(state.setId);
          expect(
            s!.status,
            ExecutionStatus.executed,
            reason: 'SET should be bound after grace period expires',
          );
        },
      );

      test(
        'grace period 0 — SET evaluated immediately (no suppression)',
        () async {
          // Grace period = 0 means the engine evaluates from windowStart.
          const contractId = 'c-no-grace';
          final windowStart = DateTime.utc(2026, 3, 1, 6, 0);
          await seedPlanWithGracePeriod(planRepo, contractId, 1, 0);

          final state = makeExecState(
            contractId: contractId,
            windowStart: windowStart,
            windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
          );
          await repo.save(state);

          // t0: immediately at window start
          final t0 = DateTime.utc(2026, 3, 1, 6, 0, 0);
          await engine.processVehicleState(
            makeVehicleState(),
            nowUtc: t0,
            organizationId: 'org-1',
          );

          final t31 = DateTime.utc(2026, 3, 1, 6, 0, 31);
          await engine.processVehicleState(
            makeVehicleState(),
            nowUtc: t31,
            organizationId: 'org-1',
          );

          final s = await repo.findBySetId(state.setId);
          expect(
            s!.status,
            ExecutionStatus.executed,
            reason: 'With grace=0, engine should bind immediately after dwell',
          );
        },
      );
    });

    // ── Rules Evaluation ───────────────────────────────────────

    group('Rules Evaluation', () {
      test('minGeofenceCoverage updates requiredDwell from config', () async {
        await seedPlanWithRules(planRepo, 'c-dwell', 1, [
          const RuleSnapshotItem(
            ruleId: 'r-dwell',
            ruleType: SlaRuleType.minGeofenceCoverage,
            config: {'min_dwell_seconds': 10},
            ruleVersion: 1,
            evaluationOrder: 1,
          ),
        ]);
        final state = makeExecState(contractId: 'c-dwell');
        await repo.save(state);

        final vehicle = makeVehicleState();
        final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
        final t11 = DateTime.utc(2026, 3, 1, 6, 30, 11);

        await engine.processVehicleState(
          vehicle,
          nowUtc: t0,
          organizationId: 'org-1',
        );
        await engine.processVehicleState(
          vehicle,
          nowUtc: t11,
          organizationId: 'org-1',
        );

        final result = await repo.findBySetId('set-1');
        expect(
          result!.status,
          ExecutionStatus.executed,
          reason: 'Dwell 10s should be enough',
        );
      });

      test('excessiveSpeed rule triggers SANCTION_RECOMMENDED', () async {
        await seedPlanWithRules(planRepo, 'c-speed', 1, [
          const RuleSnapshotItem(
            ruleId: 'r-speed',
            ruleType: SlaRuleType.excessiveSpeed,
            config: {'max_speed_kmh': 60, 'fine_cents': 200000},
            ruleVersion: 1,
            evaluationOrder: 1,
          ),
        ]);
        // contractualValue must cover the fine: cap = (20000000 * 100) ~/ 10000 = 200000
        final state = makeExecState(
          contractId: 'c-speed',
          contractualValue: const Money(20000000),
        );
        await repo.save(state);

        final vehicle = makeVehicleState().copyWith(
          smoothedSpeed: 85.0,
        ); // 25kmh over limit
        final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);

        await engine.processVehicleState(
          vehicle,
          nowUtc: t0,
          organizationId: 'org-1',
        );

        final entries = ledger.entries
            .where((e) => e.type == 'SANCTION_RECOMMENDED')
            .toList();
        expect(entries, hasLength(1));
        expect(entries.first.payload['verdict_evidence']['fine_cents'], 200000);
        expect(entries.first.payload['verdict_evidence']['delta_value'], 25.0);
      });

      test('rules are processed in evaluationOrder (sorting logic)', () async {
        final traceRepo = InMemoryEvaluationTraceRepository();
        engine = ContractualEvaluationEngine(
          executionRepo: repo,
          planRepo: planRepo,
          ledgerRepo: ledger,
          traceRepo: traceRepo,
        );

        await seedPlanWithRules(planRepo, 'c-sort', 1, [
          const RuleSnapshotItem(
            ruleId: 'r-2',
            ruleType: SlaRuleType.excessiveSpeed,
            config: {'max_speed_kmh': 10},
            ruleVersion: 1,
            evaluationOrder: 2,
          ),
          const RuleSnapshotItem(
            ruleId: 'r-1',
            ruleType: SlaRuleType.minGeofenceCoverage,
            config: {'min_dwell_seconds': 100},
            ruleVersion: 1,
            evaluationOrder: 1,
          ),
        ]);
        final state = makeExecState(contractId: 'c-sort');
        await repo.save(state);

        final vehicle = makeVehicleState().copyWith(smoothedSpeed: 20.0);
        await engine.processVehicleState(
          vehicle,
          nowUtc: vehicle.lastRawPingAt,
          organizationId: 'org-1',
        );

        await engine.processVehicleState(
          vehicle,
          nowUtc: vehicle.lastRawPingAt.add(const Duration(seconds: 101)),
          organizationId: 'org-1',
        );

        final committedTraces = await traceRepo.findByEntityId('set-1');
        expect(committedTraces, isNotEmpty);
        final decisions = committedTraces.first.decisions;

        expect(decisions[0].ruleId, 'r-1');
        expect(decisions[1].ruleId, 'r-2');
      });
    });
  });
}
