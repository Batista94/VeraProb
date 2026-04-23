import 'package:equatable/equatable.dart';

/// Read model: aggregated summary of SLA execution states.
///
/// One summary per contract (or global if contractId is null).
/// Immutable projection — no domain logic.
class SlaExecutionSummary extends Equatable {
  final String? contractId;
  final int totalPlanned;
  final int totalInTransit;
  final int totalCompleted;
  final int totalCompletedWithGaps;
  final int totalFailed;
  final DateTime generatedAtUtc;

  // ── Financial Projections ──────────────────────────────────
  final int protectedRevenue;
  final int revenueAtRisk;
  final int lostRevenue;

  const SlaExecutionSummary({
    this.contractId,
    required this.totalPlanned,
    this.totalInTransit = 0,
    required this.totalCompleted,
    required this.totalCompletedWithGaps,
    required this.totalFailed,
    required this.generatedAtUtc,
    this.protectedRevenue = 0,
    this.revenueAtRisk = 0,
    this.lostRevenue = 0,
  });

  factory SlaExecutionSummary.empty({required DateTime generatedAtUtc}) =>
      SlaExecutionSummary(
        totalPlanned: 0,
        totalCompleted: 0,
        totalCompletedWithGaps: 0,
        totalFailed: 0,
        generatedAtUtc: generatedAtUtc,
      );

  int get total =>
      totalPlanned +
      totalInTransit +
      totalCompleted +
      totalCompletedWithGaps +
      totalFailed;

  @override
  List<Object?> get props => [
    contractId,
    totalPlanned,
    totalInTransit,
    totalCompleted,
    totalCompletedWithGaps,
    totalFailed,
    generatedAtUtc,
    protectedRevenue,
    revenueAtRisk,
    lostRevenue,
  ];
}
