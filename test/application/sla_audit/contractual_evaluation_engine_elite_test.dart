import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/evaluation_trace.dart';
import 'package:veraprob/domain/sla_audit/evidence_payload.dart';

import 'evaluation_engine/_elite_test_helpers.dart';

void main() {
  late InMemoryContractualExecutionStateRepository repo;
  late InMemoryPlanDeclarationRepository planRepo;
  late InMemorySlaAuditLedgerRepository ledger;
  late InMemoryEvaluationTraceRepository traceRepo;
  late ContractualEvaluationEngine engine;

  setUpAll(initializeTimezones);

  setUp(() {
    final deps = createTestEngine();
    repo = deps.repo;
    planRepo = deps.planRepo;
    ledger = deps.ledger;
    traceRepo = deps.traceRepo;
    engine = deps.engine;
  });

  // ── Group 1: Idempotency Tests (INV-11) ─────────────────────────────────

  group('Idempotency — Duplicate processing (INV-11)', () {
    const contractId = 'c-idem';
    const setId = 'set-idem';

    test(
      'Duplicate vehicle state with same timestamp creates only ONE SANCTION_RECOMMENDED',
      () async {
        final windowStart = DateTime.utc(2026, 3, 1, 6, 0);
        final windowEnd = DateTime.utc(2026, 3, 1, 7, 0);
        final state = makeExecState(
          setId: setId,
          contractId: contractId,
          windowStart: windowStart,
          windowEnd: windowEnd,
        );
        await repo.save(state);
        await seedPlanWithExcessiveSpeedRule(
          planRepo,
          contractId,
          1,
          maxSpeedKmh: 60,
          fineCents: 200000,
        );

        final t0 = DateTime.utc(2026, 3, 1, 6, 10, 0);
        await engine.processVehicleState(
          makeVehicleAtTime(
            latitude: geoLat,
            longitude: geoLng,
            timestamp: t0,
          ).copyWith(smoothedSpeed: 85.0),
          nowUtc: t0,
          organizationId: 'org-1',
        );
        await engine.processVehicleState(
          makeVehicleAtTime(
            latitude: geoLat,
            longitude: geoLng,
            timestamp: t0,
          ).copyWith(smoothedSpeed: 85.0),
          nowUtc: t0,
          organizationId: 'org-1',
        );

        final sanctions = ledger.entries
            .where((e) => e.type == 'SANCTION_RECOMMENDED')
            .toList();
        expect(
          sanctions,
          hasLength(1),
          reason:
              'Duplicate processing must NOT create duplicate ledger entries (INV-11)',
        );
        final evidence =
            sanctions.first.payload['verdict_evidence'] as Map<String, dynamic>;
        expect(evidence['fine_cents'], 150);
      },
    );

    test(
      'Different timestamps create separate SANCTION_RECOMMENDED entries',
      () async {
        final state = makeExecState(
          setId: setId,
          contractId: contractId,
          windowStart: DateTime.utc(2026, 3, 1, 6, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        );
        await repo.save(state);
        await seedPlanWithExcessiveSpeedRule(
          planRepo,
          contractId,
          1,
          maxSpeedKmh: 60,
          fineCents: 200000,
        );

        final t0 = DateTime.utc(2026, 3, 1, 6, 10, 0);
        await engine.processVehicleState(
          makeVehicleAtTime(
            latitude: geoLat,
            longitude: geoLng,
            timestamp: t0,
          ).copyWith(smoothedSpeed: 85.0),
          nowUtc: t0,
          organizationId: 'org-1',
        );
        final t5 = DateTime.utc(2026, 3, 1, 6, 15, 0);
        await engine.processVehicleState(
          makeVehicleAtTime(
            latitude: geoLat,
            longitude: geoLng,
            timestamp: t5,
          ).copyWith(smoothedSpeed: 85.0),
          nowUtc: t5,
          organizationId: 'org-1',
        );

        final sanctions = ledger.entries
            .where((e) => e.type == 'SANCTION_RECOMMENDED')
            .toList();
        expect(sanctions, hasLength(2));
      },
    );
  });

  // ── Group 2: Forensic Chain Tests ───────────────────────────────────────

  group('Forensic Chain — DecisionId propagation', () {
    const contractId = 'c-forensic';
    const setId = 'set-forensic';

    test(
      'SANCTION_RECOMMENDED carries full VerdictEvidence with decision context',
      () async {
        final state = makeExecState(
          setId: setId,
          contractId: contractId,
          windowStart: DateTime.utc(2026, 3, 1, 6, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        );
        await repo.save(state);
        await seedPlanWithExcessiveSpeedRule(
          planRepo,
          contractId,
          1,
          maxSpeedKmh: 60,
          fineCents: 200000,
        );

        final t0 = DateTime.utc(2026, 3, 1, 6, 10, 0);
        await engine.processVehicleState(
          makeVehicleAtTime(
            latitude: geoLat,
            longitude: geoLng,
            timestamp: t0,
          ).copyWith(smoothedSpeed: 85.0),
          nowUtc: t0,
          organizationId: 'org-1',
        );

        final sanctions = ledger.entries
            .where((e) => e.type == 'SANCTION_RECOMMENDED')
            .toList();
        expect(sanctions, hasLength(1));

        final evidence =
            sanctions.first.payload['verdict_evidence'] as Map<String, dynamic>;
        expect(evidence['rule_id'], isNotEmpty);
        expect(evidence['rule_version'], isNotNull);
        expect(evidence['rule_version'], greaterThan(0));
        expect(evidence['evidence_hash'], isNotEmpty);
        expect(evidence['confidence_score'], greaterThan(0));
        expect(evidence['fine_cents'], 150);
      },
    );
  });

  // ── Group 3: Monetary Precision Tests ───────────────────────────────────

  group('Monetary Precision — 5-minute threshold tolerance', () {
    const contractId = 'c-threshold';
    const setId = 'set-threshold';

    /// Helper: processes two pings to satisfy dwell and commit delay decisions.
    /// Returns the evaluation trace after commit.
    Future<EvaluationTrace?> processDelayAndGetTrace({
      int? delayMinutes,
      Duration? delay,
      int toleranceMinutes = 5,
      int penaltyPerMinuteCents = 200,
    }) async {
      final windowStart = DateTime.utc(2026, 3, 1, 6, 0);
      final totalDelay = delay ?? Duration(minutes: delayMinutes ?? 0);

      // To ensure the final commit happens AT the desired totalDelay,
      // we make the first ping earlier.
      final arrivalTime = windowStart
          .add(totalDelay)
          .subtract(const Duration(seconds: 31));

      final state = makeExecState(
        setId: setId,
        contractId: contractId,
        windowStart: windowStart,
        windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
      );
      await repo.save(state);
      await seedPlanWithDelayRule(
        planRepo,
        contractId,
        1,
        toleranceMinutes: toleranceMinutes,
        penaltyPerMinuteCents: penaltyPerMinuteCents,
      );

      // First ping: enters geofence
      await engine.processVehicleState(
        makeVehicleAtTime(
          latitude: geoLat,
          longitude: geoLng,
          timestamp: arrivalTime,
        ),
        nowUtc: arrivalTime,
        organizationId: 'org-1',
      );

      // Second ping: exactly totalDelay from windowStart
      final commitTime = windowStart.add(totalDelay);
      await engine.processVehicleState(
        makeVehicleAtTime(
          latitude: geoLat,
          longitude: geoLng,
          timestamp: commitTime,
        ),
        nowUtc: commitTime,
        organizationId: 'org-1',
      );

      final traces = await traceRepo.findByEntityId(setId);
      return traces.isEmpty ? null : traces.first;
    }

    test('delay < 5 minutes → no DELAY_PENALTY_ASSESSED in trace', () async {
      final trace = await processDelayAndGetTrace(delayMinutes: 4);
      final delayDecisions =
          trace?.decisions
              .where((d) => d.outcome == 'DELAY_PENALTY_ASSESSED')
              .toList() ??
          [];
      expect(delayDecisions, isEmpty);
    });

    test(
      'delay = 5 minutes → no DELAY_PENALTY_ASSESSED in trace (at threshold, still free)',
      () async {
        final trace = await processDelayAndGetTrace(delayMinutes: 5);
        final delayDecisions =
            trace?.decisions
                .where((d) => d.outcome == 'DELAY_PENALTY_ASSESSED')
                .toList() ??
            [];
        expect(delayDecisions, isEmpty);
      },
    );

    test(
      'delay = 6 minutes → DELAY_PENALTY_ASSESSED with finalPenaltyCents=200 (1 billable minute)',
      () async {
        final trace = await processDelayAndGetTrace(delayMinutes: 6);
        expect(trace, isNotNull, reason: 'Expected trace after commit');
        final delayDecision = trace!.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
          orElse: () => throw TestFailure('No DELAY_PENALTY_ASSESSED in trace'),
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;
        expect(evidence.billableMinutes, 1);
        expect(evidence.finalPenaltyCents, 200);
      },
    );

    test(
      'FORENSIC PRECISION [CX-02]: delay = 300s (5min) → no penalty',
      () async {
        final trace = await processDelayAndGetTrace(
          delay: const Duration(seconds: 300),
        );
        final delayDecisions =
            trace?.decisions
                .where((d) => d.outcome == 'DELAY_PENALTY_ASSESSED')
                .toList() ??
            [];
        expect(
          delayDecisions,
          isEmpty,
          reason: '300s is exactly 5min tolerance',
        );
      },
    );

    test(
      'FORENSIC PRECISION [CX-02]: delay = 301s (5min 1s) → 1 min penalty (ceil logic)',
      () async {
        final trace = await processDelayAndGetTrace(
          delay: const Duration(seconds: 301),
        );
        expect(trace, isNotNull);
        final delayDecision = trace!.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;
        expect(
          evidence.billableMinutes,
          1,
          reason: '301s > 300s tolerance → 1s triggers 1 whole minute penalty',
        );
        expect(evidence.finalPenaltyCents, 200);
      },
    );

    test(
      'delay = 10 minutes → DELAY_PENALTY_ASSESSED with finalPenaltyCents=1000 (5 billable minutes)',
      () async {
        final trace = await processDelayAndGetTrace(delayMinutes: 10);
        expect(trace, isNotNull, reason: 'Expected trace after commit');
        final delayDecision = trace!.decisions.firstWhere(
          (d) => d.outcome == 'DELAY_PENALTY_ASSESSED',
          orElse: () => throw TestFailure('No DELAY_PENALTY_ASSESSED in trace'),
        );
        final evidence = delayDecision.evidence as DelayPenaltyEvidence;
        expect(evidence.billableMinutes, 5);
        expect(evidence.finalPenaltyCents, 1000);
      },
    );
  });

  // ── Group 4: BPS Rounding Accuracy Tests ────────────────────────────────

  group('Monetary Precision — BPS symmetric rounding', () {
    test('base=10000, bps=500 → (10000*500+5000)~/10000 = 500', () {
      verifySymmetricRounding(baseCents: 10000, bps: 500, expectedCents: 500);
    });

    test('base=10000, bps=1200 → (10000*1200+5000)~/10000 = 1200', () {
      verifySymmetricRounding(baseCents: 10000, bps: 1200, expectedCents: 1200);
    });

    test('base=15000, bps=100 (cap) → (15000*100+5000)~/10000 = 150', () {
      verifySymmetricRounding(baseCents: 15000, bps: 100, expectedCents: 150);
    });

    test('rounding: base=10001, bps=500 → (10001*500+5000)~/10000 = 500', () {
      // (10001*500+5000) = 5_005_500 ~/ 10000 = 500
      verifySymmetricRounding(baseCents: 10001, bps: 500, expectedCents: 500);
    });
  });

  // ── Group 5: Input Resilience Tests ─────────────────────────────────────

  group('Input Resilience — Corrupted input handling', () {
    const contractId = 'c-resilience';
    const setId = 'set-resilience';

    test(
      'Missing vehicleId (empty string) throws SlaEvaluationException',
      () async {
        final state = makeExecState(
          setId: setId,
          contractId: contractId,
          windowStart: DateTime.utc(2026, 3, 1, 6, 0),
          windowEnd: DateTime.utc(2026, 3, 1, 7, 0),
        );
        await repo.save(state);
        await seedPlanWithDelayRule(
          planRepo,
          contractId,
          1,
          toleranceMinutes: 5,
          penaltyPerMinuteCents: 200,
        );

        final vehicle = makeVehicleStateMissingId();
        await expectLater(
          () => engine.processVehicleState(
            vehicle,
            nowUtc: vehicle.lastRawPingAt,
            organizationId: 'org-1',
          ),
          throwsA(
            isA<SlaEvaluationException>().having(
              (e) => e.message,
              'message',
              contains('vehicleId'),
            ),
          ),
        );

        verifyLedgerEntryCount(ledger, 0);
      },
    );

    test('SlaEvaluationException message is non-empty and descriptive', () {
      const ex = SlaEvaluationException('vehicleId is required');
      expect(ex.message, isNotEmpty);
      expect(ex.message, contains('vehicleId'));
    });
  });
}
