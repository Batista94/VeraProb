/// Immutable DTO carrying raw primitive data for a single
/// contractual service execution.
///
/// Used by [DeclareContractualPlanCommand] to transport input data
/// from external layers into the Application Layer without exposing
/// domain entities.
///
/// Contains NO validation, NO methods, NO identity generation.
/// All invariant enforcement happens inside
/// [ContractualServiceExecution.create()].
class ContractualServiceInput {
  final DateTime scheduledStartTimeUtc;
  final DateTime scheduledEndTimeUtc;

  final double startLatitude; // Physical Metric - Double Required
  final double startLongitude; // Physical Metric - Double Required
  final int startRadiusMeters;

  final double endLatitude; // Physical Metric - Double Required
  final double endLongitude; // Physical Metric - Double Required
  final int endRadiusMeters;
  final String? plannedVehicleId;
  final int contractualValueCents;
  final int noShowPenaltyBps;

  const ContractualServiceInput({
    required this.scheduledStartTimeUtc,
    required this.scheduledEndTimeUtc,
    required this.startLatitude,
    required this.startLongitude,
    required this.startRadiusMeters,
    required this.endLatitude,
    required this.endLongitude,
    required this.endRadiusMeters,
    this.plannedVehicleId,
    required this.contractualValueCents,
    required this.noShowPenaltyBps,
  });
}
