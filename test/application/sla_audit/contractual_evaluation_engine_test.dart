import 'package:flutter_test/flutter_test.dart';

import 'evaluation_engine/_engine_test_helpers.dart';

// ── Skill Insight: INV-5 (BPS Precision), INV-6 (UTC), INV-15 (Deterministic)
// ── INV-23 (SANCTION_RECOMMENDED carries VerdictEvidence)
//
// Coverage targets:
//   1. False Positive  — minGeofenceCoverage, dwell ≥ 30s → ExecutionStatus.completed,
//                        ledger has ZERO SANCTION_RECOMMENDED entries.
//   2. Relentless Fine — noShowPenalty BPS cap (INV-5):
//                        contractualValue=15000, noShowPenaltyBps=15000
//                        raw = (15000 * 15000 + 5000) ~/ 10000 = 22500
//                        cap = (15000 *   100 + 5000) ~/ 10000 =   150
//                        → fineCents = 150 (cap enforced)

void main() {
  setUpAll(initializeTimezones);

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

  // ── Group 1: False Positive ──────────────────────────────────────────────

  group('False Positive — minGeofenceCoverage dwell met', () {
    const contractId = 'c-fp';
    const setId = 'set-fp';

    test(
      'vehicle inside geofence ≥ 30s → status executed, zero SANCTION_RECOMMENDED',
      () async {
        // Arrange
        final windowStart = DateTime.utc(2026, 3, 1, 6, 0);
        final windowEnd = DateTime.utc(2026, 3, 1, 7, 0);
        final state = makeExecState(
          setId: setId,
          contractId: contractId,
          windowStart: windowStart,
          windowEnd: windowEnd,
        );
        await repo.save(state);
        await seedPlanWithDwellRule(planRepo, contractId, 1);

        // Act — ping 1: vehicle enters geofence at 06:30:00
        final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
        await engine.processVehicleState(
          makeVehicleAtTime(latitude: geoLat, longitude: geoLng, timestamp: t0),
          nowUtc: t0,
          organizationId: 'org-1',
        );

        // Act — ping 2: still inside geofence, 31 seconds later (dwell ≥ 30s)
        final t31 = DateTime.utc(2026, 3, 1, 6, 30, 31);
        await engine.processVehicleState(
          makeVehicleAtTime(
            latitude: geoLat,
            longitude: geoLng,
            timestamp: t31,
          ),
          nowUtc: t31,
          organizationId: 'org-1',
        );

        // Assert: state is now executed
        final updated = await repo.findBySetId(setId);
        expect(
          updated!.status,
          ExecutionStatus.completed,
          reason: 'bindExecution must fire once dwell threshold is met',
        );

        // Assert: no financial penalty emitted (false positive)
        final sanctions = ledger.entries
            .where((e) => e.type == 'SANCTION_RECOMMENDED')
            .toList();
        expect(
          sanctions,
          isEmpty,
          reason:
              'minGeofenceCoverage success must NOT emit SANCTION_RECOMMENDED',
        );
      },
    );

    test(
      'vehicle inside geofence < 30s → state transitions to inTransit (dwell not met)',
      () async {
        // Arrange
        final state = makeExecState(
          setId: setId,
          contractId: contractId,
          windowStart: DateTime.utc(2026, 3, 1, 6, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        );
        await repo.save(state);
        await seedPlanWithDwellRule(planRepo, contractId, 1);

        // Act — single ping inside geofence, dwell NOT yet met
        final t0 = DateTime.utc(2026, 3, 1, 6, 30, 0);
        await engine.processVehicleState(
          makeVehicleAtTime(latitude: geoLat, longitude: geoLng, timestamp: t0),
          nowUtc: t0,
          organizationId: 'org-1',
        );

        // Assert: state transitions to inTransit (geofence entry detected, dwell not yet met)
        final updated = await repo.findBySetId(setId);
        expect(
          updated!.status,
          ExecutionStatus.inTransit,
          reason:
              'First geofence entry transitions planned→inTransit; dwell not yet met so not completed',
        );
        expect(ledger.entries, isEmpty);
      },
    );
  });

  // ── Group 2: Relentless Fine — noShowPenalty BPS cap ────────────────────

  group('Relentless Fine — noShowPenalty BPS cap (INV-5)', () {
    const contractId = 'c-fine';
    const setId = 'set-fine';

    // contractualValue = Money(15000), noShowPenaltyBps = 15000 (from makeExecState defaults)
    // INV-5: raw = (15000 * 15000 + 5000) ~/ 10000 = 22500
    //        cap = (15000 *   100 + 5000) ~/ 10000 =   150
    //        22500 > 150  →  penaltyCents = 150

    test(
      'sweep emits SANCTION_RECOMMENDED with fineCents capped at 100 BPS = 150',
      () async {
        // Arrange
        final windowEnd = DateTime.utc(2026, 3, 1, 7, 0);
        final state = makeExecState(
          setId: setId,
          contractId: contractId,
          windowStart: DateTime.utc(2026, 3, 1, 6, 0),
          windowEnd: windowEnd,
        );
        await repo.save(state);
        await seedPlanWithPenaltyRule(planRepo, contractId, 1);

        // Act — sweep 5 minutes after window expiry
        final sweepNow = DateTime.utc(2026, 3, 1, 7, 5);
        await engine.sweepExpiredObligations(
          nowUtc: sweepNow,
          organizationId: 'org-1',
        );

        // Assert: state marked as noShow
        final updated = await repo.findBySetId(setId);
        expect(
          updated!.status,
          ExecutionStatus.failed,
          reason: 'sweepExpiredObligations must mark state as noShow',
        );

        // Assert: SANCTION_RECOMMENDED emitted
        final sanctions = ledger.entries
            .where((e) => e.type == 'SANCTION_RECOMMENDED')
            .toList();
        expect(
          sanctions,
          hasLength(1),
          reason: 'Exactly one SANCTION_RECOMMENDED entry expected',
        );

        // Assert: fine_cents is capped at 100 BPS of contractualValue (INV-5)
        final evidence =
            sanctions.first.payload['verdict_evidence'] as Map<String, dynamic>;
        expect(
          evidence['fine_cents'],
          150,
          reason:
              'INV-5 BPS cap: (15000 * 100 + 5000) ~/ 10000 = 150; '
              'raw (15000 * 15000 + 5000) ~/ 10000 = 22500 exceeds cap',
        );

        // Assert: verdict_evidence is forensically complete (INV-23)
        expect(evidence['rule_id'], isNotEmpty);
        expect(evidence['evidence_hash'], isNotEmpty);
        expect(evidence['confidence_score'], 100);
      },
    );

    test(
      'sweep without noShowPenalty rule emits NO SANCTION_RECOMMENDED',
      () async {
        // Arrange: plan with only a dwell rule — no noShowPenalty trigger
        final state = makeExecState(
          setId: setId,
          contractId: contractId,
          windowStart: DateTime.utc(2026, 3, 1, 6, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        );
        await repo.save(state);
        await seedPlanWithDwellRule(planRepo, contractId, 1);

        // Act
        await engine.sweepExpiredObligations(
          nowUtc: DateTime.utc(2026, 3, 1, 7, 5),
          organizationId: 'org-1',
        );

        // Assert: noShow declared but no financial sanction
        final updated = await repo.findBySetId(setId);
        expect(updated!.status, ExecutionStatus.failed);
        final sanctions = ledger.entries
            .where((e) => e.type == 'SANCTION_RECOMMENDED')
            .toList();
        expect(
          sanctions,
          isEmpty,
          reason: 'No noShowPenalty rule → no SANCTION_RECOMMENDED emitted',
        );
      },
    );
  });
}
