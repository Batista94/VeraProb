import 'package:equatable/equatable.dart';

import '../shared/money.dart';

/// Financial severity tier for alert prioritization.
///
/// Thresholds (in R$):
/// - low:      < R$50
/// - medium:   R$50 – R$199.99
/// - high:     R$200 – R$499.99
/// - critical: >= R$500
enum AlertSeverityTier {
  low,
  medium,
  high,
  critical;

  /// Derives the tier from the maximum financial exposure in cents.
  static AlertSeverityTier fromCents(int cents) {
    if (cents >= 50000) return critical;
    if (cents >= 20000) return high;
    if (cents >= 5000) return medium;
    return low;
  }
}

/// Value object representing the financial impact heuristic for an alert.
///
/// Used by the OCC to prioritize alerts by projected monetary loss.
/// All monetary fields use [Money] (BIGINT cents — INV-19).
///
/// Three factory constructors cover the main alert scenarios:
/// - [delay]: billable minutes × penalty-per-minute
/// - [noShow]: base trip value × no-show multiplier
/// - [kinematicAnomalyRisk]: exposure at risk from GPS anomaly
class AlertFinancialImpact extends Equatable {
  /// Projected penalty that will be applied if the situation continues.
  final Money projectedPenaltyCents;

  /// Total financial exposure at risk (may not materialize into a penalty).
  final Money exposureAtRiskCents;

  /// Number of anomalous events contributing to this impact.
  final int anomalyCount;

  /// Computed severity tier based on the maximum financial exposure.
  final AlertSeverityTier tier;

  const AlertFinancialImpact._({
    required this.projectedPenaltyCents,
    required this.exposureAtRiskCents,
    required this.anomalyCount,
    required this.tier,
  });

  /// Delay-based impact: `delayMinutes × penaltyPerMinute`.
  factory AlertFinancialImpact.delay({
    required int delayMinutes,
    required Money penaltyPerMinute,
  }) {
    final penaltyCents = Money(delayMinutes * penaltyPerMinute.cents);
    return AlertFinancialImpact._(
      projectedPenaltyCents: penaltyCents,
      exposureAtRiskCents: penaltyCents,
      anomalyCount: 0,
      tier: AlertSeverityTier.fromCents(penaltyCents.cents),
    );
  }

  /// No-show impact: `baseTripValue × noShowMultiplier`.
  factory AlertFinancialImpact.noShow({
    required Money baseTripValue,
    required int noShowPenaltyBps,
  }) {
    final penaltyCents = baseTripValue.multiplyByBps(noShowPenaltyBps);
    return AlertFinancialImpact._(
      projectedPenaltyCents: penaltyCents,
      exposureAtRiskCents: penaltyCents,
      anomalyCount: 0,
      tier: AlertSeverityTier.fromCents(penaltyCents.cents),
    );
  }

  /// Kinematic anomaly risk: exposure is the trip value at stake,
  /// but no penalty is projected yet (requires manual review).
  factory AlertFinancialImpact.kinematicAnomalyRisk({
    required Money affectedTripValue,
    required int anomalyCount,
  }) {
    return AlertFinancialImpact._(
      projectedPenaltyCents: const Money(0),
      exposureAtRiskCents: affectedTripValue,
      anomalyCount: anomalyCount,
      tier: AlertSeverityTier.fromCents(affectedTripValue.cents),
    );
  }

  @override
  List<Object?> get props => [
    projectedPenaltyCents,
    exposureAtRiskCents,
    anomalyCount,
    tier,
  ];
}
