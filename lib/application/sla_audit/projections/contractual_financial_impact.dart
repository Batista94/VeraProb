import 'package:equatable/equatable.dart';

/// Read model: financial impact derived from contractual financial snapshots.
///
/// Executive financial view — conservative projection where pending
/// obligations are considered at-risk revenue.
/// Immutable projection — no domain logic.
///
/// All monetary values are stored as integer cents (INV-19).
class ContractualFinancialImpact extends Equatable {
  final String? contractId;
  final DateTime generatedAtUtc;
  final int totalContractedRevenue;
  final int protectedRevenue;
  final int revenueAtRisk;
  final int lostRevenue;
  final int riskPercentageBps;
  final int lossPercentageBps;

  /// Penalty erosion relative to the contract's financial ceiling.
  ///
  /// `lostRevenue / financialCeiling × 100`. Null when no ceiling is set.
  /// > 100% means the ceiling has been exceeded.
  final int? marginErosionBps;

  const ContractualFinancialImpact({
    this.contractId,
    required this.generatedAtUtc,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentageBps,
    required this.lossPercentageBps,
    this.marginErosionBps,
  });

  @override
  List<Object?> get props => [
    contractId,
    generatedAtUtc,
    totalContractedRevenue,
    protectedRevenue,
    revenueAtRisk,
    lostRevenue,
    riskPercentageBps,
    lossPercentageBps,
    marginErosionBps,
  ];
}
