import 'package:equatable/equatable.dart';

/// Read model: aggregated summary of SLA execution states.
///
/// One summary per contract (or global if contractId is null).
/// Immutable projection — no domain logic.
class SlaExecutionSummary extends Equatable {
  final String? contractId;
  final int totalPending;
  final int totalExecuted;
  final int totalNoShow;
  final int totalEvidenceGap;
  final DateTime generatedAtUtc;

  const SlaExecutionSummary({
    this.contractId,
    required this.totalPending,
    required this.totalExecuted,
    required this.totalNoShow,
    required this.totalEvidenceGap,
    required this.generatedAtUtc,
  });

  int get total =>
      totalPending + totalExecuted + totalNoShow + totalEvidenceGap;

  @override
  List<Object?> get props => [
    contractId,
    totalPending,
    totalExecuted,
    totalNoShow,
    totalEvidenceGap,
    generatedAtUtc,
  ];
}
