import 'package:flutter/material.dart';

import 'package:veraprob/application/shared/app_types.dart';

/// Immutable snapshot of one fully configured shift turn (Steps 1-3).
///
/// Accumulated in [_DeclareContractPlanFormState._confirmedShiftDrafts]
/// when the operator clicks "+ Adicionar Turno de Retorno". The final turn
/// is never stored here — it is read from the live controllers in `_submit`.
class ShiftDraftSnapshot {
  final String originZoneId;
  final String destinationZoneId;
  final String originZoneName;
  final String destinationZoneName;
  final Set<int> selectedDays;
  final TimeOfDay arrivalTime;
  final TimeOfDay departureTime;
  final String timezone;
  final VehicleCategory requiredVehicleCategory;
  final int baseValueCents;
  final int delayToleranceMinutes;
  final int earlyArrivalToleranceMinutes;
  final int dwellTimeMinutes;
  final int noShowPenaltyBps;
  final int noShowThresholdMinutes;
  final int delayPenaltyCentsPerMinute;
  final int downgradePenaltyCents;
  final int gracePeriodMinutes;
  final WeekCycle weekCycle;

  const ShiftDraftSnapshot({
    required this.originZoneId,
    required this.destinationZoneId,
    required this.originZoneName,
    required this.destinationZoneName,
    required this.selectedDays,
    required this.arrivalTime,
    required this.departureTime,
    required this.timezone,
    required this.requiredVehicleCategory,
    required this.baseValueCents,
    required this.delayToleranceMinutes,
    required this.earlyArrivalToleranceMinutes,
    required this.dwellTimeMinutes,
    required this.noShowPenaltyBps,
    required this.noShowThresholdMinutes,
    required this.delayPenaltyCentsPerMinute,
    required this.downgradePenaltyCents,
    required this.gracePeriodMinutes,
    required this.weekCycle,
  });
}
