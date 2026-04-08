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

  // ── INV-23: VerdictEvidence & SANCTION_RECOMMENDED ──────────────────────

  group('ContractualEvaluationEngine — Financial Snapshot & Sanctions', () {
    group('INV-23: VerdictEvidence & SANCTION_RECOMMENDED', () {
      test(
        'sweep emits SANCTION_RECOMMENDED when penalty rule present',
        () async {
          await seedPlanWithPenaltyRule(planRepo, 'c-penalty', 1);
          final state = makeExecState(
            contractId: 'c-penalty',
            windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
          );
          await repo.save(state);

          await engine.sweepExpiredObligations(
            nowUtc: DateTime.utc(2026, 3, 1, 7, 5),
            organizationId: 'org-1',
          );

          final entries = ledger.entries;
          // NO_SHOW_DECLARED + SANCTION_RECOMMENDED
          expect(entries.length, 2);
          final types = entries.map((e) => e.type).toList();
          expect(
            types,
            containsAll(['NO_SHOW_DECLARED', 'SANCTION_RECOMMENDED']),
          );
        },
      );

      test(
        'SANCTION_RECOMMENDED payload has non-null verdict_evidence',
        () async {
          await seedPlanWithPenaltyRule(planRepo, 'c-penalty-2', 1);
          // contractualValue=100000 cents, noShowPenaltyBps=15000 -> uncapped=150000
          // INV cap: (100000 * 100) ~/ 10000 = 1000 cents (100 BPS = 1%)
          final state = makeExecState(
            contractId: 'c-penalty-2',
            windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
            contractualValue: const Money(100000),
          );
          await repo.save(state);

          await engine.sweepExpiredObligations(
            nowUtc: DateTime.utc(2026, 3, 1, 7, 5),
            organizationId: 'org-1',
          );

          final recommended = ledger.entries
              .where((e) => e.type == 'SANCTION_RECOMMENDED')
              .toList();
          expect(recommended.length, 1);

          final evidence = recommended.first.payload['verdict_evidence'];
          expect(evidence, isNotNull);
          expect((evidence['evidence_hash'] as String).length, 64);
          expect(evidence['fine_cents'], 1000);
          expect(evidence['confidence_score'], 100);
        },
      );

      test(
        'engine NEVER emits VERDICT_SEALED directly (human-in-loop)',
        () async {
          await seedPlanWithPenaltyRule(planRepo, 'c-penalty-3', 1);
          final state = makeExecState(
            contractId: 'c-penalty-3',
            windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
          );
          await repo.save(state);

          await engine.sweepExpiredObligations(
            nowUtc: DateTime.utc(2026, 3, 1, 7, 5),
            organizationId: 'org-1',
          );

          final sealed = ledger.entries.where(
            (e) => e.type == 'VERDICT_SEALED',
          );
          expect(
            sealed,
            isEmpty,
            reason: 'Engine must never emit VERDICT_SEALED',
          );
        },
      );

      test('no SANCTION_RECOMMENDED without penalty rule', () async {
        await seedPlan(planRepo, 'c-no-penalty', 1); // empty RuleSnapshot
        final state = makeExecState(
          contractId: 'c-no-penalty',
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        );
        await repo.save(state);

        await engine.sweepExpiredObligations(
          nowUtc: DateTime.utc(2026, 3, 1, 7, 5),
          organizationId: 'org-1',
        );

        final recommended = ledger.entries.where(
          (e) => e.type == 'SANCTION_RECOMMENDED',
        );
        expect(recommended, isEmpty);
      });
    });
  });
}
