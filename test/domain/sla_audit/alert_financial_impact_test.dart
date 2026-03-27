import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/alert_financial_impact.dart';

void main() {
  group('AlertSeverityTier', () {
    test('fromCents returns low for <R\$50 (5000 cents)', () {
      expect(AlertSeverityTier.fromCents(4999), AlertSeverityTier.low);
      expect(AlertSeverityTier.fromCents(0), AlertSeverityTier.low);
    });

    test('fromCents returns medium for R\$50..R\$199', () {
      expect(AlertSeverityTier.fromCents(5000), AlertSeverityTier.medium);
      expect(AlertSeverityTier.fromCents(19999), AlertSeverityTier.medium);
    });

    test('fromCents returns high for R\$200..R\$499', () {
      expect(AlertSeverityTier.fromCents(20000), AlertSeverityTier.high);
      expect(AlertSeverityTier.fromCents(49999), AlertSeverityTier.high);
    });

    test('fromCents returns critical for >=R\$500', () {
      expect(AlertSeverityTier.fromCents(50000), AlertSeverityTier.critical);
      expect(AlertSeverityTier.fromCents(999999), AlertSeverityTier.critical);
    });
  });

  group('AlertFinancialImpact', () {
    test('delay factory computes projected penalty from minutes × rate', () {
      final impact = AlertFinancialImpact.delay(
        delayMinutes: 15,
        penaltyPerMinute: const Money(500), // R$5.00/min
      );

      // 15 × 500 = 7500 cents = R$75.00
      expect(impact.projectedPenaltyCents, const Money(7500));
      expect(impact.tier, AlertSeverityTier.medium);
    });

    test('delay with zero minutes produces zero penalty', () {
      final impact = AlertFinancialImpact.delay(
        delayMinutes: 0,
        penaltyPerMinute: const Money(500),
      );

      expect(impact.projectedPenaltyCents, const Money(0));
      expect(impact.tier, AlertSeverityTier.low);
    });

    test('noShow factory uses baseTripValue × multiplier', () {
      final impact = AlertFinancialImpact.noShow(
        baseTripValue: const Money(10000), // R$100.00
        noShowMultiplier: 2.0,
      );

      // R$100 × 2.0 = R$200.00 = 20000 cents
      expect(impact.projectedPenaltyCents, const Money(20000));
      expect(impact.tier, AlertSeverityTier.high);
    });

    test('noShow with multiplier 1.0 returns baseTripValue', () {
      final impact = AlertFinancialImpact.noShow(
        baseTripValue: const Money(3000), // R$30.00
        noShowMultiplier: 1.0,
      );

      expect(impact.projectedPenaltyCents, const Money(3000));
      expect(impact.tier, AlertSeverityTier.low);
    });

    test('kinematicAnomalyRisk uses exposure at risk', () {
      final impact = AlertFinancialImpact.kinematicAnomalyRisk(
        affectedTripValue: const Money(25000), // R$250.00
        anomalyCount: 3,
      );

      expect(impact.exposureAtRiskCents, const Money(25000));
      expect(impact.projectedPenaltyCents, const Money(0));
      expect(impact.tier, AlertSeverityTier.high);
    });

    test('kinematicAnomalyRisk with small value is low tier', () {
      final impact = AlertFinancialImpact.kinematicAnomalyRisk(
        affectedTripValue: const Money(2000), // R$20.00
        anomalyCount: 1,
      );

      expect(impact.tier, AlertSeverityTier.low);
    });

    test('Equatable: same values are equal', () {
      final a = AlertFinancialImpact.delay(
        delayMinutes: 10,
        penaltyPerMinute: const Money(100),
      );
      final b = AlertFinancialImpact.delay(
        delayMinutes: 10,
        penaltyPerMinute: const Money(100),
      );
      expect(a, equals(b));
    });

    test('tier thresholds are correct at boundaries', () {
      // Exactly R$50.00 = medium
      final medium = AlertFinancialImpact.delay(
        delayMinutes: 10,
        penaltyPerMinute: const Money(500), // 10 × 500 = 5000
      );
      expect(medium.tier, AlertSeverityTier.medium);

      // Exactly R$200.00 = high
      final high = AlertFinancialImpact.delay(
        delayMinutes: 20,
        penaltyPerMinute: const Money(1000), // 20 × 1000 = 20000
      );
      expect(high.tier, AlertSeverityTier.high);

      // Exactly R$500.00 = critical
      final critical = AlertFinancialImpact.delay(
        delayMinutes: 50,
        penaltyPerMinute: const Money(1000), // 50 × 1000 = 50000
      );
      expect(critical.tier, AlertSeverityTier.critical);
    });
  });
}
