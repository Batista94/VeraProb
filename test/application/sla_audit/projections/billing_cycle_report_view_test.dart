import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/billing_cycle_report_view.dart';

void main() {
  group('BillingCycleReportView', () {
    test('can be constructed with required fields', () {
      final view = BillingCycleReportView(
        id: 'bcr-1',
        organizationId: 'org-1',
        periodStartUtc: DateTime.utc(2026, 3, 1),
        periodEndUtc: DateTime.utc(2026, 3, 31),
        totalContractedRevenueCents: 1000000,
        protectedRevenueCents: 950000,
        revenueAtRiskCents: 50000,
        lostRevenueCents: 12000,
        totalObligations: 120,
        executedCount: 115,
        noShowCount: 3,
        evidenceGapCount: 2,
        complianceRateBps: 9583,
        generatedAtUtc: DateTime.utc(2026, 4, 1),
        isComplete: true,
      );
      expect(view.id, 'bcr-1');
      expect(view.isComplete, isTrue);
    });

    test('all financial fields are int (INV-2 compliance)', () {
      final view = BillingCycleReportView(
        id: 'bcr-2',
        organizationId: 'org-1',
        periodStartUtc: DateTime.utc(2026, 3, 1),
        periodEndUtc: DateTime.utc(2026, 3, 31),
        totalContractedRevenueCents: 500000,
        protectedRevenueCents: 490000,
        revenueAtRiskCents: 10000,
        lostRevenueCents: 5000,
        totalObligations: 50,
        executedCount: 48,
        noShowCount: 1,
        evidenceGapCount: 1,
        complianceRateBps: 9600,
        generatedAtUtc: DateTime.utc(2026, 4, 1),
        isComplete: false,
      );
      expect(view.totalContractedRevenueCents, isA<int>());
      expect(view.protectedRevenueCents, isA<int>());
      expect(view.revenueAtRiskCents, isA<int>());
      expect(view.lostRevenueCents, isA<int>());
      expect(view.complianceRateBps, isA<int>());
    });

    test('complianceRateBps 9583 = 95.83% (BPS not double)', () {
      final view = BillingCycleReportView(
        id: 'bcr-3',
        organizationId: 'org-1',
        periodStartUtc: DateTime.utc(2026, 3, 1),
        periodEndUtc: DateTime.utc(2026, 3, 31),
        totalContractedRevenueCents: 0,
        protectedRevenueCents: 0,
        revenueAtRiskCents: 0,
        lostRevenueCents: 0,
        totalObligations: 0,
        executedCount: 0,
        noShowCount: 0,
        evidenceGapCount: 0,
        complianceRateBps: 9583,
        generatedAtUtc: DateTime.utc(2026, 4, 1),
        isComplete: false,
      );
      expect(view.complianceRateBps, 9583);
    });

    test('contractId is optional', () {
      final view = BillingCycleReportView(
        id: 'bcr-4',
        organizationId: 'org-1',
        periodStartUtc: DateTime.utc(2026, 3, 1),
        periodEndUtc: DateTime.utc(2026, 3, 31),
        totalContractedRevenueCents: 0,
        protectedRevenueCents: 0,
        revenueAtRiskCents: 0,
        lostRevenueCents: 0,
        totalObligations: 0,
        executedCount: 0,
        noShowCount: 0,
        evidenceGapCount: 0,
        complianceRateBps: 0,
        generatedAtUtc: DateTime.utc(2026, 4, 1),
        isComplete: false,
      );
      expect(view.contractId, isNull);
    });
  });
}
