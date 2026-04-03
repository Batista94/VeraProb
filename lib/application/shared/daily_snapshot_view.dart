import 'package:veraprob/domain/sla_audit/contractual_financial_daily_snapshot.dart';

/// Read model for a daily financial snapshot used in the presentation layer.
class DailySnapshotView {
  final String id;
  final DateTime operationalDateUtc;
  final int totalContractedRevenue;
  final int protectedRevenue;
  final int revenueAtRisk;
  final int lostRevenue;
  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;
  final int riskPercentageBps;
  final int lossPercentageBps;
  final String? lastLedgerEntryId;

  const DailySnapshotView({
    required this.id,
    required this.operationalDateUtc,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.riskPercentageBps,
    required this.lossPercentageBps,
    this.lastLedgerEntryId,
  });

  factory DailySnapshotView.fromDomain(
    ContractualFinancialDailySnapshot domain,
  ) {
    return DailySnapshotView(
      id: domain.id,
      operationalDateUtc: domain.operationalDateUtc,
      totalContractedRevenue: domain.totalContractedRevenue.cents,
      protectedRevenue: domain.protectedRevenue.cents,
      revenueAtRisk: domain.revenueAtRisk.cents,
      lostRevenue: domain.lostRevenue.cents,
      totalObligations: domain.totalObligations,
      executedCount: domain.executedCount,
      noShowCount: domain.noShowCount,
      evidenceGapCount: domain.evidenceGapCount,
      riskPercentageBps: domain.riskPercentageBps,
      lossPercentageBps: domain.lossPercentageBps,
      lastLedgerEntryId: domain.lastLedgerEntryId,
    );
  }
}
