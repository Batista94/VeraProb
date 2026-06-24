import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/money.dart';

/// Per-(organization, contract) carrier compliance scorecard row.
///
/// Projected by the `get_carrier_performance_ranking` RPC over the
/// `mv_carrier_performance` materialized view. Obligation counts come from
/// `shadow_verdicts`; [disputeCount] and [fineExposure] from
/// `sanction_review_queue`.
///
/// **Rates are integer basis points (INV-5):** [complianceRateBps] 8000 = 80.00%.
class CarrierPerformanceRank extends Equatable {
  final String organizationId;
  final String contractId;
  final int totalObligations;
  final int executedCount;
  final int noShowCount;
  final int evidenceGapCount;
  final int falsePositiveCount;
  final int falseNegativeCount;

  /// Executed / total obligations, in basis points (0–10000).
  final int complianceRateBps;
  final int disputeCount;

  /// Disputes / total obligations, in basis points (0–10000).
  final int disputeRateBps;

  /// Sum of `fine_cents` across all sanctions for this contract (INV-4).
  final Money fineExposure;

  /// Most recent shadow verdict timestamp for this contract (UTC). Null when
  /// the contract has obligations but none carry an engine timestamp.
  final DateTime? lastEvaluatedUtc;

  const CarrierPerformanceRank({
    required this.organizationId,
    required this.contractId,
    required this.totalObligations,
    required this.executedCount,
    required this.noShowCount,
    required this.evidenceGapCount,
    required this.falsePositiveCount,
    required this.falseNegativeCount,
    required this.complianceRateBps,
    required this.disputeCount,
    required this.disputeRateBps,
    required this.fineExposure,
    required this.lastEvaluatedUtc,
  });

  factory CarrierPerformanceRank.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => (v as num).toInt();
    return CarrierPerformanceRank(
      organizationId: json['organization_id'] as String,
      contractId: json['contract_id'] as String,
      totalObligations: asInt(json['total_obligations']),
      executedCount: asInt(json['executed_count']),
      noShowCount: asInt(json['no_show_count']),
      evidenceGapCount: asInt(json['evidence_gap_count']),
      falsePositiveCount: asInt(json['false_positive_count']),
      falseNegativeCount: asInt(json['false_negative_count']),
      complianceRateBps: asInt(json['compliance_rate_bps']),
      disputeCount: asInt(json['dispute_count']),
      disputeRateBps: asInt(json['dispute_rate_bps']),
      fineExposure: Money(asInt(json['total_fine_exposure_cents'])),
      lastEvaluatedUtc: json['last_evaluated_utc'] == null
          ? null
          : DateTime.parse(json['last_evaluated_utc'] as String).toUtc(),
    );
  }

  @override
  List<Object?> get props => [
    organizationId,
    contractId,
    totalObligations,
    executedCount,
    noShowCount,
    evidenceGapCount,
    falsePositiveCount,
    falseNegativeCount,
    complianceRateBps,
    disputeCount,
    disputeRateBps,
    fineExposure,
    lastEvaluatedUtc,
  ];
}
