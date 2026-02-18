class VehiclePosition {
  final String tripId;
  final double latitude;
  final double longitude;
  final double? speed;
  final double? heading;
  final DateTime timestamp;
  final String source; // 'api_public' or 'driver_app_gps'

  final String? routeName; // e.g. "Term. Lapa", "809U-10"

  VehiclePosition({
    required this.tripId,
    required this.latitude,
    required this.longitude,
    this.speed,
    this.heading,
    required this.timestamp,
    required this.source,
    this.routeName,
  });
}
