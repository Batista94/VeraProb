class RawTelemetryBatch {
  final String deviceId;
  final String organizationId;
  final String callerUserId;
  final List<TelemetryCoordinate> coordinates;

  RawTelemetryBatch({
    required this.deviceId,
    required this.organizationId,
    required this.callerUserId,
    required this.coordinates,
  });
}

class TelemetryCoordinate {
  final double latitude; // Physical Metric - Double Required
  final double longitude; // Physical Metric - Double Required
  final DateTime occurredAt;

  TelemetryCoordinate({
    required this.latitude,
    required this.longitude,
    required this.occurredAt,
  });
}
