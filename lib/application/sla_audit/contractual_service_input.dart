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

  /// GPS Latitude - Precision Required
  final double startLatitude;

  /// GPS Longitude - Precision Required
  final double startLongitude;
  final int startRadiusMeters;

  /// GPS Latitude - Precision Required
  final double endLatitude;

  /// GPS Longitude - Precision Required
  final double endLongitude;
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
