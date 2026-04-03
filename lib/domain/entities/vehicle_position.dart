import 'package:equatable/equatable.dart';

/// A GPS position record for a vehicle, with source tracking.
class VehiclePosition extends Equatable {
  final String? id;
  final String tripId;
  final double latitude; // Physical Metric - Double Required
  final double longitude; // Physical Metric - Double Required
  final double? speed; // Physical Metric - Double Required
  final double? heading; // Physical Metric - Double Required
  final DateTime timestamp;
  final String source; // 'api_public' or 'driver_app_gps'

  // Denormalized display fields
  final String? routeName;
  final String? vehiclePlate;

  const VehiclePosition({
    this.id,
    required this.tripId,
    required this.latitude,
    required this.longitude,
    this.speed,
    this.heading,
    required this.timestamp,
    required this.source,
    this.routeName,
    this.vehiclePlate,
  });

  /// Whether this position is considered stale (older than threshold)
  bool isStale({Duration threshold = const Duration(minutes: 2)}) {
    return DateTime.now().toUtc().difference(timestamp) > threshold;
  }

  factory VehiclePosition.fromJson(Map<String, dynamic> json) {
    return VehiclePosition(
      id: json['id']?.toString(),
      tripId: json['trip_id'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      speed: (json['speed'] as num?)?.toDouble(),
      heading: (json['heading'] as num?)?.toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      source: json['source'] as String,
      routeName: json['route_name'] as String?,
      vehiclePlate: json['vehicle_plate'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'trip_id': tripId,
      'latitude': latitude,
      'longitude': longitude,
      'speed': speed,
      'heading': heading,
      'timestamp': timestamp.toIso8601String(),
      'source': source,
    };
  }

  @override
  List<Object?> get props => [
    id,
    tripId,
    latitude,
    longitude,
    speed,
    heading,
    timestamp,
    source,
  ];
}
