import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/shared/money.dart';

/// Mutable form model for the SLA Penalties wizard step.
///
/// Intentionally mutable — bound to form fields. All financial fields
/// are `int` (BPS or cents — INV-2). Use [toDomain] to produce an
/// immutable [SLAPenalties] VO when committing the form.
class PenaltiesFormData {
  int noShowPenaltyBps;
  int delayToleranceMinutes;
  int delayPenaltyPerMinuteCents;
  int downgradePenaltyFlatCents;
  int noShowThresholdMinutes;
  int earlyArrivalToleranceMinutes;
  int dwellTimeMinutes;
  int gracePeriodMinutes;
  int baseTripValueCents;

  PenaltiesFormData({
    required this.noShowPenaltyBps,
    required this.delayToleranceMinutes,
    required this.delayPenaltyPerMinuteCents,
    required this.downgradePenaltyFlatCents,
    required this.noShowThresholdMinutes,
    required this.earlyArrivalToleranceMinutes,
    required this.dwellTimeMinutes,
    required this.gracePeriodMinutes,
    required this.baseTripValueCents,
  });

  /// Sensible defaults for the wizard when no template is selected.
  factory PenaltiesFormData.defaults() {
    return PenaltiesFormData(
      noShowPenaltyBps: 10000,
      delayToleranceMinutes: 10,
      delayPenaltyPerMinuteCents: 500,
      downgradePenaltyFlatCents: 5000,
      noShowThresholdMinutes: 60,
      earlyArrivalToleranceMinutes: 5,
      dwellTimeMinutes: 3,
      gracePeriodMinutes: 0,
      baseTripValueCents: 0,
    );
  }

  factory PenaltiesFormData.fromDomain(SLAPenalties penalties) {
    return PenaltiesFormData(
      noShowPenaltyBps: penalties.noShowPenaltyBps,
      delayToleranceMinutes: penalties.delayToleranceMinutes,
      delayPenaltyPerMinuteCents: penalties.delayPenaltyPerMinute.cents,
      downgradePenaltyFlatCents: penalties.downgradePenaltyFlat.cents,
      noShowThresholdMinutes: penalties.noShowThresholdMinutes,
      earlyArrivalToleranceMinutes: penalties.earlyArrivalToleranceMinutes,
      dwellTimeMinutes: penalties.dwellTimeMinutes,
      gracePeriodMinutes: penalties.gracePeriodMinutes,
      baseTripValueCents: penalties.baseTripValue.cents,
    );
  }

  SLAPenalties toDomain() {
    return SLAPenalties.create(
      noShowPenaltyBps: noShowPenaltyBps,
      delayToleranceMinutes: delayToleranceMinutes,
      delayPenaltyPerMinute: Money(delayPenaltyPerMinuteCents),
      downgradePenaltyFlat: Money(downgradePenaltyFlatCents),
      noShowThresholdMinutes: noShowThresholdMinutes,
      earlyArrivalToleranceMinutes: earlyArrivalToleranceMinutes,
      dwellTimeMinutes: dwellTimeMinutes,
      gracePeriodMinutes: gracePeriodMinutes,
      baseTripValue: Money(baseTripValueCents),
    );
  }
}
