class CanonicalFact {
  final String deviceId;
  final DateTime occurredAt;
  final double latitude; // Physical Metric - Double Required
  final double longitude; // Physical Metric - Double Required
  final String organizationId;

  CanonicalFact({
    required this.deviceId,
    required this.occurredAt,
    required this.latitude,
    required this.longitude,
    required this.organizationId,
  });
}
