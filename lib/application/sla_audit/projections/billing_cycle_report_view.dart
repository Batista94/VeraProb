import 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';

/// Flat read model for [BillingCycleReport] used in presentation layer.
///
/// All financial fields are `int` (cents or BPS — INV-2).
class BillingCycleReportView {
  final String id;
  final String organizationId;
  final String? contractId;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final int totalContractedRevenueCents;
  final int protectedRevenueCents;
  final int revenueAtRiskCents;
  final int lostRevenueCents;
  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;

  /// Compliance rate in BPS (e.g. 9583 = 95.83%).
  final int complianceRateBps;
  final DateTime generatedAtUtc;
  final bool isComplete;

  const BillingCycleReportView({
    required this.id,
    required this.organizationId,
    this.contractId,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.totalContractedRevenueCents,
    required this.protectedRevenueCents,
    required this.revenueAtRiskCents,
    required this.lostRevenueCents,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.complianceRateBps,
    required this.generatedAtUtc,
    required this.isComplete,
  });

  factory BillingCycleReportView.fromDomain(BillingCycleReport report) {
    return BillingCycleReportView(
      id: report.id,
      organizationId: report.organizationId,
      contractId: report.contractId,
      periodStartUtc: report.periodStartUtc,
      periodEndUtc: report.periodEndUtc,
      totalContractedRevenueCents: report.totalContractedRevenue.cents,
      protectedRevenueCents: report.protectedRevenue.cents,
      revenueAtRiskCents: report.revenueAtRisk.cents,
      lostRevenueCents: report.lostRevenue.cents,
      totalObligations: report.totalObligations,
      executedCount: report.executedCount,
      noShowCount: report.noShowCount,
      evidenceGapCount: report.evidenceGapCount,
      complianceRateBps: report.complianceRateBps,
      generatedAtUtc: report.generatedAtUtc,
      isComplete: report.isComplete,
    );
  }
}
