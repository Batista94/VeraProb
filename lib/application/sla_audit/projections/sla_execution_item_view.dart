import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/sla_audit/execution_status.dart';
import 'package:veraprob/domain/shared/money.dart';

/// Read model: individual SET obligation view for lists and drill-down.
///
/// Flat projection from [ContractualExecutionState] aggregate.
/// Immutable — no domain logic.
class SlaExecutionItemView extends Equatable {
  final String setId;
  final String contractId;
  final ExecutionStatus status;
  final DateTime windowStartUtc;
  final DateTime windowEndUtc;
  final String? plannedVehicleId;
  final String? boundVehicleId;
  final DateTime? boundAtUtc;

  final double startLatitude; // Physical Metric - Double Required
  final double startLongitude; // Physical Metric - Double Required
  final int startRadiusMeters;
  final int contractualValue;
  final int noShowPenaltyBps;

  const SlaExecutionItemView({
    required this.setId,
    required this.contractId,
    required this.status,
    required this.windowStartUtc,
    required this.windowEndUtc,
    this.plannedVehicleId,
    this.boundVehicleId,
    this.boundAtUtc,
    required this.startLatitude,
    required this.startLongitude,
    required this.startRadiusMeters,
    required this.contractualValue,
    required this.noShowPenaltyBps,
  });

  /// Computed penalty value for display purposes.
  /// Formula lives here (projection layer), not in the UI.
  /// Calculates the no-show penalty using Symmetric Rounding (INV-19).
  /// Formula: `(contractualValue * noShowPenaltyBps + 5000) ~/ 10000`.
  int get calculatedPenalty =>
      Money(contractualValue).multiplyByBps(noShowPenaltyBps).cents;

  @override
  List<Object?> get props => [
    setId,
    contractId,
    status,
    windowStartUtc,
    windowEndUtc,
    plannedVehicleId,
    boundVehicleId,
    boundAtUtc,
    startLatitude,
    startLongitude,
    startRadiusMeters,
    contractualValue,
    noShowPenaltyBps,
  ];
}
