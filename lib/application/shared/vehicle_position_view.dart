import 'package:veraprob/domain/entities/vehicle_position.dart';

/// Read model for vehicle position used in the presentation layer.
///
/// [latitude] and [longitude] are `double` — Physical Metric - Double Required.
/// [speed] and [heading] are `double?` — Physical Metric - Double Required.
class VehiclePositionView {
  final String tripId;
  final double latitude; // Physical Metric - Double Required
  final double longitude; // Physical Metric - Double Required
  final double? speed; // Physical Metric - Double Required
  final double? heading; // Physical Metric - Double Required
  final DateTime timestamp;
  final String source;
  final String? routeName;

  const VehiclePositionView({
    required this.tripId,
    required this.latitude,
    required this.longitude,
    this.speed,
    this.heading,
    required this.timestamp,
    required this.source,
    this.routeName,
  });

  factory VehiclePositionView.fromDomain(VehiclePosition domain) {
    return VehiclePositionView(
      tripId: domain.tripId,
      latitude: domain.latitude,
      longitude: domain.longitude,
      speed: domain.speed,
      heading: domain.heading,
      timestamp: domain.timestamp,
      source: domain.source,
      routeName: domain.routeName,
    );
  }
}
