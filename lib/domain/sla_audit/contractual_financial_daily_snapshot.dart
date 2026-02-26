import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../shared/money.dart';

/// Immutable daily financial snapshot for contractual SLA obligations.
///
/// Represents the financial state of a contract (or all contracts) for a
/// specific operational day. Once created, cannot be modified — this ensures
/// auditability and prevents historical recalculation.
///
/// The [operationalDateUtc] is the normalized UTC date (00:00Z) derived
/// from the Brazil operational timezone (America/Sao_Paulo).
class ContractualFinancialDailySnapshot extends Equatable {
  final String id;
  final String? contractId;

  /// Operational day in normalized UTC (00:00Z).
  final DateTime operationalDateUtc;

  /// Timezone used to derive the operational day.
  final String operationalTimezone;

  /// Exact UTC instant when this snapshot was generated.
  final DateTime closedAtUtc;

  final Money totalContractedRevenue;
  final Money protectedRevenue;
  final Money revenueAtRisk;
  final Money lostRevenue;

  final double riskPercentage;
  final double lossPercentage;

  const ContractualFinancialDailySnapshot._({
    required this.id,
    required this.contractId,
    required this.operationalDateUtc,
    required this.operationalTimezone,
    required this.closedAtUtc,
    required this.totalContractedRevenue,
    required this.protectedRevenue,
    required this.revenueAtRisk,
    required this.lostRevenue,
    required this.riskPercentage,
    required this.lossPercentage,
  });

  /// Creates a new immutable daily financial snapshot.
  ///
  /// Percentages are calculated automatically from the monetary values.
  /// [operationalDateUtc] is normalized to midnight UTC.
  static ContractualFinancialDailySnapshot create({
    required String? contractId,
    required DateTime operationalDateUtc,
    required String operationalTimezone,
    required DateTime closedAtUtc,
    required Money totalContractedRevenue,
    required Money protectedRevenue,
    required Money revenueAtRisk,
    required Money lostRevenue,
  }) {
    final normalizedDate = DateTime.utc(
      operationalDateUtc.year,
      operationalDateUtc.month,
      operationalDateUtc.day,
    );

    final totalCents = totalContractedRevenue.cents;
    final riskPercentage = totalCents > 0
        ? revenueAtRisk.cents / totalCents * 100
        : 0.0;
    final lossPercentage = totalCents > 0
        ? lostRevenue.cents / totalCents * 100
        : 0.0;

    return ContractualFinancialDailySnapshot._(
      id: const Uuid().v4(),
      contractId: contractId,
      operationalDateUtc: normalizedDate,
      operationalTimezone: operationalTimezone,
      closedAtUtc: closedAtUtc,
      totalContractedRevenue: totalContractedRevenue,
      protectedRevenue: protectedRevenue,
      revenueAtRisk: revenueAtRisk,
      lostRevenue: lostRevenue,
      riskPercentage: riskPercentage,
      lossPercentage: lossPercentage,
    );
  }

  @override
  List<Object?> get props => [
    id,
    contractId,
    operationalDateUtc,
    operationalTimezone,
    closedAtUtc,
    totalContractedRevenue,
    protectedRevenue,
    revenueAtRisk,
    lostRevenue,
    riskPercentage,
    lossPercentage,
  ];
}
