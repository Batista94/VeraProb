import 'package:equatable/equatable.dart';

/// Read model: financial snapshot for a specific UTC date.
///
/// Part of the time-series financial trend projection.
/// Immutable — no domain logic. Built from persisted daily snapshots.
///
/// All monetary values are stored as integer cents (INV-19).
class ContractualFinancialTrendPoint extends Equatable {
  final DateTime dateUtc;
  final String formattedDate;
  final int baseRevenueUsedForCalculation;
  final int totalContractedRevenue;
  final int protectedRevenue;
  final int revenueAtRisk;
  final int lostRevenue;
  final int riskPercentageBps;
  final int lossPercentageBps;

  const ContractualFinancialTrendPoint({
    required this.dateUtc,
    required this.formattedDate,
    required this.baseRevenueUsedForCalculation,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentageBps,
    required this.lossPercentageBps,
  });

  @override
  List<Object?> get props => [
    dateUtc,
    formattedDate,
    baseRevenueUsedForCalculation,
    totalContractedRevenue,
    protectedRevenue,
    revenueAtRisk,
    lostRevenue,
    riskPercentageBps,
    lossPercentageBps,
  ];
}
