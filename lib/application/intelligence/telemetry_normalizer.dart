import 'dart:math' show cos, sqrt, asin;
import 'package:veraprob/application/intelligence/ping_classification.dart';
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'package:veraprob/domain/sla_audit/telemetry/spoofing_detected_exception.dart';

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
  ///
  /// Thin backward-compatible delegate over [classifyPing] — preserves the
  /// `VehiclePosition?` contract for stream consumers that only care whether a
  /// ping survived, not why it was dropped.
  VehiclePosition? processPing(RawTelemetryPing ping) {
    final classification = classifyPing(ping);
    return classification is PingAccepted ? classification.position : null;
  }

  /// Classifies a raw ping against all sensor-sanitization heuristics.
  ///
  /// Returns [PingAccepted] with the clean position, or [PingRejected] with the
  /// concrete [PingRejectionReason] — the auditable form of [processPing].
  PingClassification classifyPing(RawTelemetryPing ping) {
    final accuracyFailure = _checkAccuracy(ping);
    if (accuracyFailure != null) return PingRejected(accuracyFailure);

    final lastPing = _lastValidPings[ping.vehicleId];
    final kinematicFailure = _checkKinematics(ping, lastPing);
    if (kinematicFailure != null) return PingRejected(kinematicFailure);

    // Ping is valid. Save as last known good ping.
    _lastValidPings[ping.vehicleId] = ping;
    return PingAccepted(_toPosition(ping));
  }

  /// Sensor sanitization — accuracy radius and emulator-signature checks.
  PingRejectionReason? _checkAccuracy(RawTelemetryPing ping) {
    if (ping.accuracy > maxAccuracyMeters) {
      return PingRejectionReason.lowAccuracy;
    }
    // INV-18: real GPS devices have stdDev >= 0.001 due to atmospheric noise.
    if (ping.accuracy < 0.001) {
      return PingRejectionReason.emulatorSignature;
    }
    return null;
  }

  /// Sensor sanitization — Haversine implied-speed jump and same-timestamp
  /// movement checks against the last valid ping for this vehicle.
  PingRejectionReason? _checkKinematics(
    RawTelemetryPing ping,
    RawTelemetryPing? lastPing,
  ) {
    if (lastPing == null) return null;

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
      final impliedSpeedKmh = (distanceMeters / timeDiffSeconds) * 3.6;
      if (impliedSpeedKmh > maxImpliedSpeedKmh) {
        return PingRejectionReason.impossibleSpeedJump;
      }
    } else if (distanceMeters > 5.0) {
      return PingRejectionReason.sameTimestampMovement;
    }
    return null;
  }

  /// Converts a validated raw ping into the clean domain entity.
  VehiclePosition _toPosition(RawTelemetryPing ping) {
    return VehiclePosition(
      id: ping.vehicleId,
      tripId: ping.tripId,
      latitude: ping.latitude,
      longitude: ping.longitude,
      heading: ping.heading,
      speed: ping.speed,
      timestamp: ping.timestamp,
      source: 'driver_app_gps',
    );
  }

  /// Calculates the great-circle distance between two points on the Earth surface using the Haversine formula.
  /// Returns distance in meters.
  double _calculateDistance(
    // Physical Metric - Double Required
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

  /// Validates a batch of coordinates for zero-variance spoofing.
  /// Throws SpoofingDetectedException if synthetic pattern detected.
  void validateBatch(List<RawTelemetryPing> pings, String deviceId) {
    if (pings.length < 5) return;

    final latitudes = pings.map((p) => p.latitude).toSet();
    final longitudes = pings.map((p) => p.longitude).toSet();

    if (latitudes.length == 1 && longitudes.length == 1) {
      throw SpoofingDetectedException(
        deviceId: deviceId,
        reason:
            'zero variance detected in batch of ${pings.length} coordinates',
      );
    }
  }
}
