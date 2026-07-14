// pr_scanner: ignore-regression — PR elevation org-scope ports / domain touch (Council-approved plan)
import 'package:equatable/equatable.dart';

/// Represents a raw, unfiltered GPS ping straight from the device hardware.
/// This information is "dirty" and must pass through the Normalizer before becoming a VehiclePosition.
class RawTelemetryPing extends Equatable {
  final String vehicleId;
  final String tripId;
  final double latitude; // Physical Metric - Double Required
  final double longitude; // Physical Metric - Double Required
  final double accuracy; // In meters // Physical Metric - Double Required
  final double
  speed; // In meters per second // Physical Metric - Double Required
  final double heading; // 0-359 degrees // Physical Metric - Double Required
  final DateTime timestamp;

  const RawTelemetryPing({
    required this.vehicleId,
    required this.tripId,
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.heading,
    required this.timestamp,
  });

  factory RawTelemetryPing.fromJson(Map<String, dynamic> json) {
    return RawTelemetryPing(
      vehicleId: json['vehicle_id'] as String,
      tripId: json['trip_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      accuracy: (json['accuracy'] as num).toDouble(),
      speed: (json['speed'] as num).toDouble(),
      heading: (json['heading'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vehicle_id': vehicleId,
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracy': accuracy,
      'speed': speed,
      'heading': heading,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    vehicleId,
    tripId,
    latitude,
    longitude,
    accuracy,
    speed,
    heading,
    timestamp,
  ];
}
