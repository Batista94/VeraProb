import 'package:flutter_test/flutter_test.dart';
import 'package:pactaflow/domain/sla_audit/domain_exception.dart';
import 'package:pactaflow/domain/sla_audit/shadow_mode_simulation.dart';
import 'package:pactaflow/domain/shared/money.dart';

void main() {
  final periodStart = DateTime.utc(2026, 3, 1);
  final periodEnd = DateTime.utc(2026, 3, 31, 23, 59, 59);
  final generatedAt = DateTime.utc(2026, 4, 1, 1, 0, 0);

  ShadowModeSimulation makeSimulation({
    String orgId = 'org-abc',
    Money actualLostRevenue = const Money(100000), // R$ 1000.00
    double baselineDisputeRate = 60.0, // 60% would have been disputed away
    int incidentCount = 10,
    Money manualCostPerIncident = const Money(5000), // R$ 50.00
    Money platformSubscriptionCost = const Money(50000), // R$ 500.00
    double evidenceQualityRate = 95.0,
  }) =>
      ShadowModeSimulation.compute(
        organizationId: orgId,
        simulationName: 'Março 2026',
        periodStartUtc: periodStart,
        periodEndUtc: periodEnd,
        actualProtectedRevenue: const Money(800000),
        actualLostRevenue: actualLostRevenue,
        actualAtRiskRevenue: const Money(50000),
        actualComplianceRate: 85.0,
        evidenceQualityRate: evidenceQualityRate,
        baselineDisputeRate: baselineDisputeRate,
        manualEnforcementCostPerIncident: manualCostPerIncident,
        incidentCount: incidentCount,
        platformSubscriptionCost: platformSubscriptionCost,
        generatedAtUtc: generatedAt,
        generatedByUserId: 'user-manager-1',
      );

  // ── ROI computation ────────────────────────────────────────────────────────
  group('ShadowModeSimulation.compute — ROI calculation', () {
    test('simulatedLostRevenue = actualLost × (1 − disputeRate/100)', () {
      // actualLost = R$ 1000 (100000 cents)
      // disputeRate = 60% → 40% actually recovered without platform
      // simulated = 100000 × (1 − 0.6) = 40000 cents
      final sim = makeSimulation(
        actualLostRevenue: const Money(100000),
        baselineDisputeRate: 60.0,
        manualCostPerIncident: const Money(0),
        incidentCount: 0,
        platformSubscriptionCost: const Money(1),
      );
      expect(sim.simulatedLostRevenue.cents, 40000);
    });

    test('revenueProtectedByPlatform includes manual enforcement savings', () {
      // actualLost=100000, disputeRate=60%, simulated=40000
      // manualCost = 5000 × 10 = 50000
      // protected = (100000 - 40000) + 50000 = 110000
      final sim = makeSimulation(
        actualLostRevenue: const Money(100000),
        baselineDisputeRate: 60.0,
        manualCostPerIncident: const Money(5000),
        incidentCount: 10,
        platformSubscriptionCost: const Money(1),
      );
      expect(sim.revenueProtectedByPlatform.cents, 110000);
    });

    test('roiPercentage = (protected / subscriptionCost) × 100', () {
      // protected=110000, subscription=50000
      // roi = (110000 / 50000) × 100 = 220.0
      final sim = makeSimulation(
        actualLostRevenue: const Money(100000),
        baselineDisputeRate: 60.0,
        manualCostPerIncident: const Money(5000),
        incidentCount: 10,
        platformSubscriptionCost: const Money(50000),
      );
      expect(sim.roiPercentage, closeTo(220.0, 0.01));
    });

    test('roiPercentage is 0 when subscription cost is 0', () {
      final sim = makeSimulation(
        platformSubscriptionCost: const Money(0),
      );
      expect(sim.roiPercentage, 0.0);
    });

    test('same inputs produce same results (idempotency)', () {
      final sim1 = makeSimulation();
      final sim2 = makeSimulation();
      expect(sim1.simulatedLostRevenue.cents, sim2.simulatedLostRevenue.cents);
      expect(sim1.revenueProtectedByPlatform.cents, sim2.revenueProtectedByPlatform.cents);
      expect(sim1.roiPercentage, sim2.roiPercentage);
    });

    test('zero dispute rate means operator recovers nothing without platform', () {
      // disputeRate=0% → all penalties would have been successfully disputed
      // simulated = actualLost × (1-0) = actualLost
      // protected = 0 + manualCost
      final sim = makeSimulation(
        actualLostRevenue: const Money(100000),
        baselineDisputeRate: 0.0,
        manualCostPerIncident: const Money(0),
        incidentCount: 0,
        platformSubscriptionCost: const Money(1),
      );
      expect(sim.simulatedLostRevenue.cents, equals(sim.actualLostRevenue.cents));
      expect(sim.revenueProtectedByPlatform.cents, 0);
    });

    test('100% dispute rate means without platform zero recovery (full exposure)', () {
      // disputeRate=100% → all penalties waived without platform
      // simulated = actualLost × (1 - 1.0) = 0
      // protected = actualLost - 0 + manualCost
      final sim = makeSimulation(
        actualLostRevenue: const Money(100000),
        baselineDisputeRate: 100.0,
        manualCostPerIncident: const Money(0),
        incidentCount: 0,
        platformSubscriptionCost: const Money(1),
      );
      expect(sim.simulatedLostRevenue.cents, 0);
      expect(sim.revenueProtectedByPlatform.cents, 100000);
    });
  });

  // ── Validation ─────────────────────────────────────────────────────────────
  group('ShadowModeSimulation.compute — validation', () {
    test('throws if organizationId is empty', () {
      expect(
        () => makeSimulation(orgId: ''),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws if baselineDisputeRate > 100', () {
      expect(
        () => ShadowModeSimulation.compute(
          organizationId: 'org-1',
          simulationName: 'test',
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          actualProtectedRevenue: const Money(0),
          actualLostRevenue: const Money(0),
          actualAtRiskRevenue: const Money(0),
          actualComplianceRate: 100,
          evidenceQualityRate: 100,
          baselineDisputeRate: 101.0, // invalid
          manualEnforcementCostPerIncident: const Money(0),
          incidentCount: 0,
          platformSubscriptionCost: const Money(1),
          generatedAtUtc: generatedAt,
          generatedByUserId: 'user-1',
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws if evidenceQualityRate < 0', () {
      expect(
        () => ShadowModeSimulation.compute(
          organizationId: 'org-1',
          simulationName: 'test',
          periodStartUtc: periodStart,
          periodEndUtc: periodEnd,
          actualProtectedRevenue: const Money(0),
          actualLostRevenue: const Money(0),
          actualAtRiskRevenue: const Money(0),
          actualComplianceRate: 100,
          evidenceQualityRate: -1.0, // invalid
          baselineDisputeRate: 50,
          manualEnforcementCostPerIncident: const Money(0),
          incidentCount: 0,
          platformSubscriptionCost: const Money(1),
          generatedAtUtc: generatedAt,
          generatedByUserId: 'user-1',
        ),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws if any DateTime is not UTC', () {
      expect(
        () => ShadowModeSimulation.compute(
          organizationId: 'org-1',
          simulationName: 'test',
          periodStartUtc: DateTime(2026, 3, 1), // local, not UTC
          periodEndUtc: periodEnd,
          actualProtectedRevenue: const Money(0),
          actualLostRevenue: const Money(0),
          actualAtRiskRevenue: const Money(0),
          actualComplianceRate: 100,
          evidenceQualityRate: 95,
          baselineDisputeRate: 60,
          manualEnforcementCostPerIncident: const Money(0),
          incidentCount: 0,
          platformSubscriptionCost: const Money(1),
          generatedAtUtc: generatedAt,
          generatedByUserId: 'user-1',
        ),
        throwsA(isA<DomainException>()),
      );
    });
  });

  // ── Evidence quality attribution ───────────────────────────────────────────
  group('ShadowModeSimulation.evidenceQualityAttribution', () {
    test('excellent text when evidenceQualityRate >= 95', () {
      final sim = makeSimulation(evidenceQualityRate: 97.5);
      final text = sim.evidenceQualityAttribution;
      expect(text, contains('excelente'));
      expect(text, contains('97.5%'));
    });

    test('adequate text when 80 <= evidenceQualityRate < 95', () {
      final sim = makeSimulation(evidenceQualityRate: 82.0);
      final text = sim.evidenceQualityAttribution;
      expect(text, contains('adequada'));
    });

    test('warning text when evidenceQualityRate < 80 — attributes to hardware', () {
      final sim = makeSimulation(evidenceQualityRate: 65.0);
      final text = sim.evidenceQualityAttribution;
      // Must mention hardware attribution (PO directive: protect operator's legal position)
      expect(text, contains('hardware GPS'));
      expect(text, contains('contratante'));
      expect(text, contains('PactaFlow processou 100%'));
    });

    test('attribution text never blames PactaFlow for hardware issues', () {
      final sim = makeSimulation(evidenceQualityRate: 40.0);
      final text = sim.evidenceQualityAttribution;
      expect(text, isNot(contains('erro do sistema')));
      expect(text, isNot(contains('falha do PactaFlow')));
    });
  });
}
