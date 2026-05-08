/// Command for creating a planned execution via OCC operator action.
/// INV-1: org_id from JWT only. INV-6: window dates must be UTC.
class CreateExecutionCommand {
  final String organizationId;
  final String sessionId;
  final String contractId;
  final String driverId;
  final String? vehicleId;
  final String? originZoneId;
  final String? destinationZoneId;
  final DateTime windowStartUtc;
  final DateTime windowEndUtc;

  const CreateExecutionCommand({
    required this.organizationId,
    required this.sessionId,
    required this.contractId,
    required this.driverId,
    this.vehicleId,
    this.originZoneId,
    this.destinationZoneId,
    required this.windowStartUtc,
    required this.windowEndUtc,
  });
}
