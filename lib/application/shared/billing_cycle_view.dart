import 'package:veraprob/domain/sla_audit/billing_cycle_report.dart';
import 'app_types.dart';
import 'daily_snapshot_view.dart';

/// Read model for a billing cycle report used in the presentation layer.
class BillingCycleView {
  final String id;
  final String organizationId;
  final String? contractId;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;

  final int totalContractedRevenue;
  final int protectedRevenue;
  final int revenueAtRisk;
  final int lostRevenue;

  final List<DailySnapshotView> snapshots;

  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;
  final int complianceRateBps;
  final bool isComplete;
  final List<DateTime> missingDates;

  const BillingCycleView({
    required this.id,
    required this.organizationId,
    this.contractId,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.snapshots,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.complianceRateBps,
    required this.isComplete,
    required this.missingDates,
  });

  factory BillingCycleView.fromDomain(BillingCycleReport domain) {
    return BillingCycleView(
      id: domain.id,
      organizationId: domain.organizationId,
      contractId: domain.contractId,
      periodStartUtc: domain.periodStartUtc,
      periodEndUtc: domain.periodEndUtc,
      totalContractedRevenue: domain.totalContractedRevenue.cents,
      protectedRevenue: domain.protectedRevenue.cents,
      revenueAtRisk: domain.revenueAtRisk.cents,
      lostRevenue: domain.lostRevenue.cents,
      snapshots: domain.snapshots.map(DailySnapshotView.fromDomain).toList(),
      totalObligations: domain.totalObligations,
      executedCount: domain.executedCount,
      noShowCount: domain.noShowCount,
      evidenceGapCount: domain.evidenceGapCount,
      complianceRateBps: domain.complianceRateBps,
      isComplete: domain.isComplete,
      missingDates: domain.missingDates,
    );
  }
}
