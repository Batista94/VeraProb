import 'package:equatable/equatable.dart';

import '../../../domain/shared/money.dart';

/// Read model: financial snapshot for a specific UTC date.
///
/// Part of the time-series financial trend projection.
/// Immutable — no domain logic. Built from persisted daily snapshots.
class ContractualFinancialTrendPoint extends Equatable {
  final DateTime dateUtc;
  final String formattedDate;
  final Money baseRevenueUsedForCalculation;
  final Money totalContractedRevenue;
  final Money protectedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;
  final double riskPercentage;
  final double lossPercentage;

  const ContractualFinancialTrendPoint({
    required this.dateUtc,
    required this.formattedDate,
    required this.baseRevenueUsedForCalculation,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentage,
    required this.lossPercentage,
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
    riskPercentage,
    lossPercentage,
  ];
}
