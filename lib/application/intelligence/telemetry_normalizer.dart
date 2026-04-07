import 'dart:math' show cos, sqrt, asin;
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

/// The Purgatory Filter.
/// Responsible for receiving dirty RawTelemetryPings and filtering out noise,
/// impossible jumps, and converting valid pings into VehiclePositions for the State.
class TelemetryNormalizer {
  final double maxAccuracyMeters; // Physical Metric - Double Required
  final double maxImpliedSpeedKmh; // Physical Metric - Double Required

  // State to remember the last valid ping per vehicle to calculate jumps
  final Map<String, RawTelemetryPing> _lastValidPings = {};

  TelemetryNormalizer({
    this.maxAccuracyMeters = 50.0,
    this.maxImpliedSpeedKmh = 120.0,
  });

  /// Processes a raw ping. Returns a clean VehiclePosition if valid, or null if rejected.
  VehiclePosition? processPing(RawTelemetryPing ping) {
    // 1. Accuracy Filter
    if (ping.accuracy > maxAccuracyMeters) {
      return null;
    }

    final lastPing = _lastValidPings[ping.vehicleId];

    // 2. Implied Speed Filter (Haversine Jump Check)
    if (lastPing != null) {
      final distanceMeters = _calculateDistance(
        lastPing.latitude,
        lastPing.longitude,
        ping.latitude,
        ping.longitude,
      );

      final timeDiffSeconds = ping.timestamp
          .difference(lastPing.timestamp)
          .inSeconds
          .abs();

      if (timeDiffSeconds > 0) {
        final impliedSpeedMps = distanceMeters / timeDiffSeconds;
        final impliedSpeedKmh = impliedSpeedMps * 3.6;

        if (impliedSpeedKmh > maxImpliedSpeedKmh) {
          // Impossible jump detected. Discard.
          return null;
        }
      } else if (distanceMeters > 5.0) {
        // Same timestamp but moved more than 5 meters -> impossible glitch
        return null;
      }
    }

    // Ping is valid. Save as last known good ping.
    _lastValidPings[ping.vehicleId] = ping;

    // Convert to the Domain Entity
    return VehiclePosition(
      id: ping
          .vehicleId, // Optionally mapping vehicleId to position Id if needed, or leave null
      tripId: ping.tripId,
      latitude: ping.latitude,
      longitude: ping.longitude,
      heading: ping.heading,
      speed: ping.speed,
      timestamp: ping.timestamp,
      source: 'driver_app_gps', // As designed in the Domain
    );
  }

  /// Calculates the great-circle distance between two points on the Earth surface using the Haversine formula.
  /// Returns distance in meters.
  double _calculateDistance( // Physical Metric - Double Required
    double lat1, // Physical Metric - Double Required
    double lon1, // Physical Metric - Double Required
    double lat2, // Physical Metric - Double Required
    double lon2, // Physical Metric - Double Required
  ) {
    const double p = // Physical Metric - Double Required
        0.017453292519943295; // Math.PI / 180 // Physical Metric - Double Required
    final double a = // Physical Metric - Double Required
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;

    return 12742 * asin(sqrt(a)) * 1000; // 2 * R; R = 6371 km -> meters
  }

  /// Clears internal state (useful for tests or hard resets)
  void clearState() {
    _lastValidPings.clear();
  }
}
