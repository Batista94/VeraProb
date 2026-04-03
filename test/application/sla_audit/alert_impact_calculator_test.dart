import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/alert_impact_calculator.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';

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
    group('forDelay', () {
      test('computes impact for delay beyond tolerance', () {
        final penalties = _makePenalties(
          delayPenaltyPerMinute: const Money(500), // R$5.00/min
          delayToleranceMinutes: 5,
        );

        // 20 min total delay, 5 min tolerance → 15 billable minutes
        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 20,
          penalties: penalties,
        );

        // 15 × 500 = 7500 cents = R$75.00
        expect(impact.projectedPenaltyCents, const Money(7500));
        expect(impact.tier, AlertSeverityTier.medium);
      });

      test('returns zero impact when delay is within tolerance', () {
        final penalties = _makePenalties(delayToleranceMinutes: 10);

        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 5,
          penalties: penalties,
        );

        expect(impact.projectedPenaltyCents, const Money(0));
        expect(impact.tier, AlertSeverityTier.low);
      });

      test('returns zero impact when delay equals tolerance', () {
        final penalties = _makePenalties(delayToleranceMinutes: 10);

        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 10,
          penalties: penalties,
        );

        expect(impact.projectedPenaltyCents, const Money(0));
        expect(impact.tier, AlertSeverityTier.low);
      });

      test('handles zero tolerance correctly', () {
        final penalties = _makePenalties(
          delayToleranceMinutes: 0,
          delayPenaltyPerMinute: const Money(1000), // R$10/min
        );

        final impact = AlertImpactCalculator.forDelay(
          delayMinutes: 5,
          penalties: penalties,
        );

        // 5 × 1000 = 5000 = R$50.00
        expect(impact.projectedPenaltyCents, const Money(5000));
        expect(impact.tier, AlertSeverityTier.medium);
      });
    });

    group('forNoShow', () {
      test('computes impact as baseTripValue × multiplier', () {
        final penalties = _makePenalties(
          baseTripValue: const Money(15000), // R$150.00
          noShowBps: 20000,
        );

        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        // R$150 × 2.0 = R$300.00 = 30000 cents
        expect(impact.projectedPenaltyCents, const Money(30000));
        expect(impact.tier, AlertSeverityTier.high);
      });

      test('critical tier for high-value no-show', () {
        final penalties = _makePenalties(
          baseTripValue: const Money(30000), // R$300.00
          noShowBps: 20000,
        );

        final impact = AlertImpactCalculator.forNoShow(penalties: penalties);

        // R$300 × 2.0 = R$600 → critical
        expect(impact.projectedPenaltyCents, const Money(60000));
        expect(impact.tier, AlertSeverityTier.critical);
      });
    });

    group('forKinematicAnomaly', () {
      test('returns exposure at risk from affected trip value', () {
        final impact = AlertImpactCalculator.forKinematicAnomaly(
          affectedTripValue: const Money(25000), // R$250.00
          anomalyCount: 5,
        );

        expect(impact.exposureAtRiskCents, const Money(25000));
        expect(impact.projectedPenaltyCents, const Money(0));
        expect(impact.anomalyCount, 5);
        expect(impact.tier, AlertSeverityTier.high);
      });
    });
  });
}
