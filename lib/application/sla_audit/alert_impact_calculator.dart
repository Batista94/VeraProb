import '../../domain/shared/money.dart';
import '../../domain/sla_audit/alert_financial_impact.dart';

export '../../domain/sla_audit/alert_financial_impact.dart';
import '../../domain/sla_audit/sla_penalties.dart';

/// Application service that bridges [SLAPenalties] to [AlertFinancialImpact].
///
/// Computes financial impact heuristics for alert prioritization in the OCC.
/// All calculations use [Money] (BIGINT cents — INV-19).
class AlertImpactCalculator {
  AlertImpactCalculator._();

  /// Computes financial impact for a delay alert.
  ///
  /// Billable minutes = `delayMinutes - delayToleranceMinutes`.
  /// If within tolerance, returns zero impact.
  static AlertFinancialImpact forDelay({
    required int delayMinutes,
    required SLAPenalties penalties,
  }) {
    final billable = delayMinutes - penalties.delayToleranceMinutes;
    if (billable <= 0) {
      return AlertFinancialImpact.delay(
        delayMinutes: 0,
        penaltyPerMinute: penalties.delayPenaltyPerMinute,
      );
    }
    return AlertFinancialImpact.delay(
      delayMinutes: billable,
      penaltyPerMinute: penalties.delayPenaltyPerMinute,
    );
  }

  /// Computes financial impact for a no-show alert.
  ///
  /// Uses `baseTripValue × noShowPenaltyBps` from [SLAPenalties].
  static AlertFinancialImpact forNoShow({required SLAPenalties penalties}) {
    return AlertFinancialImpact.noShow(
      baseTripValue: penalties.baseTripValue,
      noShowPenaltyBps: penalties.noShowPenaltyBps,
    );
  }

  /// Computes financial exposure for a kinematic anomaly alert.
  ///
  /// No penalty is projected (requires manual review); the exposure
  /// represents the trip value that may be contested.
  static AlertFinancialImpact forKinematicAnomaly({
    required Money affectedTripValue,
    required int anomalyCount,
  }) {
    return AlertFinancialImpact.kinematicAnomalyRisk(
      affectedTripValue: affectedTripValue,
      anomalyCount: anomalyCount,
    );
  }
}
