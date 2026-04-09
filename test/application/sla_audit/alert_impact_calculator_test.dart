import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/alert_impact_calculator.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';

// ── Test Helpers ─────────────────────────────────────────────────────────────

SLAPenalties _makePenalties({
  Money delayPenaltyPerMinute = const Money(500),
  int noShowBps = 20000,
  Money baseTripValue = const Money(10000),
  int delayToleranceMinutes = 5,
  int noShowThresholdMinutes = 60,
}) {
  return SLAPenalties.create(
    noShowPenaltyBps: noShowBps,
    delayToleranceMinutes: delayToleranceMinutes,
    delayPenaltyPerMinute: delayPenaltyPerMinute,
    downgradePenaltyFlat: const Money(5000),
    noShowThresholdMinutes: noShowThresholdMinutes,
    baseTripValue: baseTripValue,
  );
}

void main() {
  group('AlertImpactCalculator', () {
    // ─────────────────────────────────────────────────────────────────────
    // Grupo 1: INV-19 — Penny Precision
    // Garante que NENHUM cálculo use double para representar dinheiro.
    // Todos os resultados são Money com cents inteiros.
    // ─────────────────────────────────────────────────────────────────────
    group('INV-19: Penny Precision', () {
      test('forDelay returns Money with integer cents, never double', () {
        final penalties = _makePenalties(
          delayPenaltyPerMinute: const Money(333),
          delayToleranceMinutes: 5,
        );

        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 17,
          penalties: penalties,
        );

        // 17 - 5 = 12 billable minutes; 12 × 333 = 3996 cents
        expect(impact.projectedPenaltyCents, isA<Money>());
        expect(impact.projectedPenaltyCents.cents, isA<int>());
        expect(impact.projectedPenaltyCents.cents, 3996);
        // Confirma que não há double envolvido
        expect(impact.projectedPenaltyCents.cents % 1, 0);
      });

      test('forNoShow uses BPS integer arithmetic, no floating-point drift', () {
        final penalties = _makePenalties(
          baseTripValue: const Money(12345), // cents ímpares
          noShowBps: 17500, // 1.75×
        );

        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        // Validação manual: (12345 * 17500) ~/ 10000 = 216037500 ~/ 10000 = 21603
        const expectedManual = (12345 * 17500) ~/ 10000;
        expect(impact.projectedPenaltyCents.cents, expectedManual);
        expect(impact.projectedPenaltyCents.cents, 21603);
        // Garante que o resultado é inteiro exato
        expect(impact.projectedPenaltyCents.cents % 1, 0);
      });

      test('kinematicAnomaly exposure is Money with integer cents', () {
        final impact = AlertImpactCalculator.forKinematicAnomaly(
          affectedTripValue: const Money(77777),
          anomalyCount: 3,
        );

        expect(impact.exposureAtRiskCents, isA<Money>());
        expect(impact.exposureAtRiskCents.cents, isA<int>());
        expect(impact.exposureAtRiskCents.cents, 77777);
        expect(impact.exposureAtRiskCents.cents % 1, 0);
      });
    });

    // ─────────────────────────────────────────────────────────────────────
    // Grupo 2: Boundary — Severity Tiers
    // Valida os limiares exatos de cada tier (em cents):
    //   low:      < 5000
    //   medium:   5000 – 19999
    //   high:     20000 – 49999
    //   critical: >= 50000
    // ─────────────────────────────────────────────────────────────────────
    group('AlertSeverityTier boundaries', () {
      test('low at 4999 cents (just below medium)', () {
        expect(AlertSeverityTier.fromCents(4999), AlertSeverityTier.low);
      });

      test('medium at exactly 5000 cents (R\$50.00)', () {
        expect(AlertSeverityTier.fromCents(5000), AlertSeverityTier.medium);
      });

      test('medium at 19999 cents (just below high)', () {
        expect(AlertSeverityTier.fromCents(19999), AlertSeverityTier.medium);
      });

      test('high at exactly 20000 cents (R\$200.00)', () {
        expect(AlertSeverityTier.fromCents(20000), AlertSeverityTier.high);
      });

      test('critical at exactly 50000 cents (R\$500.00)', () {
        expect(AlertSeverityTier.fromCents(50000), AlertSeverityTier.critical);
      });
    });

    // ─────────────────────────────────────────────────────────────────────
    // Grupo 3: Arredondamento BPS — Truncamento Inteiro (~/)
    // Valida que a operação (baseValue * bps) ~/ 10000 trunca para baixo,
    // sem arredondamento para cima.
    // ─────────────────────────────────────────────────────────────────────
    group('BPS truncation (~/ operator)', () {
      test('BPS division truncates toward zero, never rounds up', () {
        // 10001 cents × 15000 bps = 150015000; 150015000 ~/ 10000 = 15001
        // Com double seria 15001.5 → risco de round para 15002
        const baseValue = 10001;
        const bps = 15000;
        const expectedTruncated = (baseValue * bps) ~/ 10000;

        final penalties = _makePenalties(
          baseTripValue: const Money(baseValue),
          noShowBps: bps,
        );
        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        expect(impact.projectedPenaltyCents.cents, expectedTruncated);
        expect(impact.projectedPenaltyCents.cents, 15001);
        // Se usasse double .round(), daria 15002 — garantir que NÃO é isso
        expect(impact.projectedPenaltyCents.cents, isNot(15002));
      });

      test('BPS truncation discards fractional cents — proves ~/ is intentional, '
          'never .round()', () {
        // INV-19: This test is a guardrail against future "well-intentioned" devs
        // who might replace ~/ with / and .round(), introducing double drift.
        //
        // Scenario: 99999 cents × 10001 bps = 1000089999
        //   ~/ 10000 = 100008  (truncation — current behavior)
        //   /  10000 = 100008.9999 → .round() → 100009 (drift!)
        //
        // The 0.9999¢ difference is deliberate: truncation is architecturally
        // mandated to avoid IEEE-754 ambiguity and ensure deterministic results
        // across all platforms (WASM, native, server).

        const baseValue = 99999;
        const bps = 10001; // minimum valid BPS + 1 (just above identity)
        const truncated = (baseValue * bps) ~/ 10000; // 100008
        final rounded = (baseValue * bps / 10000).round(); // 100009

        // Sanity check: prove the two approaches diverge
        expect(truncated, isNot(rounded));
        expect(truncated, 100008);
        expect(rounded, 100009);

        final penalties = _makePenalties(
          baseTripValue: const Money(baseValue),
          noShowBps: bps,
        );
        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        // The calculator MUST use truncation, not rounding
        expect(impact.projectedPenaltyCents.cents, truncated);
        expect(impact.projectedPenaltyCents.cents, isNot(rounded));
      });

      test('BPS with odd cents produces deterministic truncated result', () {
        // 99999 cents × 11250 bps = 1124988750; ~/ 10000 = 112498
        // 11250 bps = 1.125× (acima do mínimo 10000)
        const baseValue = 99999;
        const bps = 11250;
        const expectedTruncated = (baseValue * bps) ~/ 10000;

        final penalties = _makePenalties(
          baseTripValue: const Money(baseValue),
          noShowBps: bps,
        );
        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        expect(impact.projectedPenaltyCents.cents, expectedTruncated);
        expect(impact.projectedPenaltyCents.cents, 112498);
      });

      test('BPS 10000 is identity multiplier (1.0×)', () {
        final penalties = _makePenalties(
          baseTripValue: const Money(42750),
          noShowBps: 10000, // exatamente 1.0×
        );
        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        expect(impact.projectedPenaltyCents.cents, 42750);
      });
    });

    // ─────────────────────────────────────────────────────────────────────
    // Grupo 4: Delay — Edge Cases
    // ─────────────────────────────────────────────────────────────────────
    group('forDelay: edge cases', () {
      test('delay of zero minutes returns zero impact', () {
        final penalties = _makePenalties(
          delayPenaltyPerMinute: const Money(1000),
          delayToleranceMinutes: 5,
        );

        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 0,
          penalties: penalties,
        );

        expect(impact.projectedPenaltyCents, const Money(0));
        expect(impact.tier, AlertSeverityTier.low);
      });

      test('delay exactly 1 minute beyond tolerance charges 1 minute', () {
        final penalties = _makePenalties(
          delayPenaltyPerMinute: const Money(750),
          delayToleranceMinutes: 10,
        );

        // 11 - 10 = 1 billable minute
        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 11,
          penalties: penalties,
        );

        expect(impact.projectedPenaltyCents, const Money(750));
        expect(impact.tier, AlertSeverityTier.low);
      });

      test('large delay produces correct multiplication', () {
        final penalties = _makePenalties(
          delayPenaltyPerMinute: const Money(200), // R$2.00/min
          delayToleranceMinutes: 10,
        );

        // 120 - 10 = 110 billable; 110 × 200 = 22000 cents = R$220.00
        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 120,
          penalties: penalties,
        );

        expect(impact.projectedPenaltyCents, const Money(22000));
        expect(impact.tier, AlertSeverityTier.high);
      });

      test(
        'billable minutes never go negative when tolerance exceeds delay',
        () {
          final penalties = _makePenalties(
            delayPenaltyPerMinute: const Money(500),
            delayToleranceMinutes: 30,
          );

          // 5 min delay, 30 min tolerance → zero, NUNCA negativo
          final impact = AlertImpactCalculator.forDelay(
            delayMinutes: 5,
            penalties: penalties,
          );

          expect(impact.projectedPenaltyCents, const Money(0));
          expect(impact.exposureAtRiskCents, const Money(0));
        },
      );
    });

    // ─────────────────────────────────────────────────────────────────────
    // Grupo 5: No-Show — Edge Cases
    // ─────────────────────────────────────────────────────────────────────
    group('forNoShow: edge cases', () {
      test('no-show with minimum BPS (10000 = 1.0×) equals base value', () {
        final penalties = _makePenalties(
          baseTripValue: const Money(50000),
          noShowBps: 10000,
        );

        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        expect(impact.projectedPenaltyCents, const Money(50000));
      });

      test('no-show with extreme BPS (50000 = 5.0×)', () {
        final penalties = _makePenalties(
          baseTripValue: const Money(10000), // R$100.00
          noShowBps: 50000, // 5×
        );

        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        // 10000 × 5 = 50000 cents = R$500.00
        expect(impact.projectedPenaltyCents, const Money(50000));
        expect(impact.tier, AlertSeverityTier.critical);
      });

      test('no-show with zero base trip value yields zero impact', () {
        final penalties = _makePenalties(
          baseTripValue: const Money(0),
          noShowBps: 20000,
        );

        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        expect(impact.projectedPenaltyCents, const Money(0));
        expect(impact.exposureAtRiskCents, const Money(0));
        expect(impact.tier, AlertSeverityTier.low);
      });
    });

    // ─────────────────────────────────────────────────────────────────────
    // Grupo 6: Integridade do Value Object
    // ─────────────────────────────────────────────────────────────────────
    group('Value Object integrity', () {
      test('Equatable equality for identical delay impacts', () {
        final penalties = _makePenalties(
          delayPenaltyPerMinute: const Money(500),
          delayToleranceMinutes: 5,
        );

        final impact1 = AlertImpactCalculator.forDelay(
          delayMinutes: 20,
          penalties: penalties,
        );
        final impact2 = AlertImpactCalculator.forDelay(
          delayMinutes: 20,
          penalties: penalties,
        );

        expect(impact1, equals(impact2));
      });

      test('delay impact has zero anomalyCount', () {
        final penalties = _makePenalties();
        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 15,
          penalties: penalties,
        );

        expect(impact.anomalyCount, 0);
      });

      test('noShow impact has zero anomalyCount', () {
        final penalties = _makePenalties();
        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        expect(impact.anomalyCount, 0);
      });

      test(
        'kinematicAnomaly has zero projectedPenalty but non-zero exposure',
        () {
          final impact = AlertImpactCalculator.forKinematicAnomaly(
            affectedTripValue: const Money(30000),
            anomalyCount: 7,
          );

          expect(impact.projectedPenaltyCents, const Money(0));
          expect(impact.exposureAtRiskCents, const Money(30000));
          expect(impact.anomalyCount, 7);
          expect(impact.tier, AlertSeverityTier.high);
        },
      );
    });
  });
}
