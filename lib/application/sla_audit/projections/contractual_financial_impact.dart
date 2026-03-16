import 'package:equatable/equatable.dart';

import '../../../domain/shared/money.dart';

/// Read model: financial impact derived from contractual financial snapshots.
///
/// Executive financial view — conservative projection where pending
/// obligations are considered at-risk revenue.
/// Immutable projection — no domain logic.
class ContractualFinancialImpact extends Equatable {
  final String? contractId;
  final DateTime generatedAtUtc;
  final Money totalContractedRevenue;
  final Money protectedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;
  final double riskPercentage;
  final double lossPercentage;

  /// Penalty erosion relative to the contract's financial ceiling.
  ///
  /// `lostRevenue / financialCeiling × 100`. Null when no ceiling is set.
  /// > 100% means the ceiling has been exceeded.
  final double? marginErosionPercent;

  const ContractualFinancialImpact({
    this.contractId,
    required this.generatedAtUtc,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentage,
    required this.lossPercentage,
    this.marginErosionPercent,
  });

  @override
  List<Object?> get props => [
    contractId,
    generatedAtUtc,
    totalContractedRevenue,
    protectedRevenue,
    revenueAtRisk,
    lostRevenue,
    riskPercentage,
    lossPercentage,
    marginErosionPercent,
  ];
}
