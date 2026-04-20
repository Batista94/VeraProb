import 'package:veraprob/core/utils/geo_math.dart';
import 'package:veraprob/domain/entities/stop.dart';
import 'models/motion_state.dart';

/// Stateful motion classifier that owns the low-speed timer per vehicle.
///
/// Tracks when each vehicle first entered a low-speed condition so that
/// [MotionState.stopped] and [MotionState.slowTraffic] transitions are
/// time-gated correctly.  The Normalizer coordinates TTL cleanup by
/// calling [removeKey] from [_cleanStaleStates].
class MotionClassifier {
  final double
  movingSpeedThreshold; // km/h // Physical Metric - Double Required
  final double
  slowTrafficThreshold; // km/h // Physical Metric - Double Required
  final Duration stoppedMinDuration;
  final Duration slowTrafficMinDuration;
  final double stopRadiusMeters; // Physical Metric - Double Required

  /// Timestamp when each vehicle first entered a low-speed state.
  final Map<String, DateTime> _lowSpeedSince = {};

  MotionClassifier({
    required this.movingSpeedThreshold,
    required this.slowTrafficThreshold,
    required this.stoppedMinDuration,
    required this.slowTrafficMinDuration,
    required this.stopRadiusMeters,
  });

  /// Classify the current [MotionState] for [vehicleId].
  ///
  /// [smoothedSpeed] — km/h from [SpatialSmoother.smoothSpeed].
  /// [position]      — (lat, lng) from [SpatialSmoother.applySmoothing].
  /// [stops]         — known transit stops for geofencing.
  /// [now]           — injectable clock (UTC).
  /// [previousPosition] — previous (lat, lng) for geographic speed calculation.
  /// [previousTimestamp] — previous timestamp for geographic speed calculation.
  /// [isFirstPing] — true if this is the first ping from this vehicle (cold start bypass).
  MotionState classifyMotion(
    String vehicleId,
    double smoothedSpeed, // Physical Metric - Double Required
    (double, double) position, // Physical Metric - Double Required
    List<Stop> stops,
    DateTime now, {
    (double, double)? previousPosition, // Physical Metric - Double Required
    DateTime? previousTimestamp,
    bool isFirstPing = false,
  }) {
    // Geographic speed detection (anti-ghost movement)
    // If device reports speed=0 but coordinates show movement, override to moving
    if (smoothedSpeed <= slowTrafficThreshold &&
        previousPosition != null &&
        previousTimestamp != null) {
      final distance = GeoMath.haversineMeters(
        previousPosition.$1,
        previousPosition.$2,
        position.$1,
        position.$2,
      );
      final elapsedSeconds =
          now.difference(previousTimestamp).inMilliseconds / 1000.0;
      if (elapsedSeconds > 0) {
        final geographicSpeed =
            (distance / elapsedSeconds) * 3.6; // m/s to km/h
        if (geographicSpeed >= movingSpeedThreshold) {
          _lowSpeedSince.remove(vehicleId);
          return MotionState.moving; // Geographic override
        }
      }
    }

    if (smoothedSpeed > movingSpeedThreshold) {
      _lowSpeedSince.remove(vehicleId);
      return MotionState.moving;
    }

    _lowSpeedSince.putIfAbsent(vehicleId, () => now);
    final lowSpeedDuration = now.difference(_lowSpeedSince[vehicleId]!);

    if (smoothedSpeed <= slowTrafficThreshold) {
      return _classifyStationary(
        vehicleId,
        position,
        stops,
        lowSpeedDuration,
        isFirstPing,
      );
    }

    // Between slowTrafficThreshold and movingSpeedThreshold
    if (lowSpeedDuration >= slowTrafficMinDuration) {
      return MotionState.slowTraffic;
    }
    return MotionState.moving;
  }

  /// Remove internal low-speed tracking entry for [key] (TTL cleanup).
  void removeKey(String key) => _lowSpeedSince.remove(key);

  /// Clear all internal state (for testing or mode switching).
  void reset() => _lowSpeedSince.clear();

  // ── Private ───────────────────────────────────────────

  MotionState _classifyStationary(
    String vehicleId,
    (double, double) position, // Physical Metric - Double Required
    List<Stop> stops,
    Duration lowSpeedDuration,
    bool isFirstPing,
  ) {
    // Cold start bypass - skip timer check for first ping
    if (!isFirstPing && lowSpeedDuration < stoppedMinDuration) {
      return MotionState.moving;
    }
    final nearStop = _findNearestStop(position.$1, position.$2, stops);
    return nearStop != null ? MotionState.dwellingAtStop : MotionState.stopped;
  }

  (String, String)? _findNearestStop(
    double lat, // Physical Metric - Double Required
    double lng, // Physical Metric - Double Required
    List<Stop> stops,
  ) {
    double minDist = double.infinity; // Physical Metric - Double Required
    Stop? nearest;

    for (final stop in stops) {
      final dist = GeoMath.haversineMeters(
        lat,
        lng,
        stop.latitude,
        stop.longitude,
      );
      if (dist < minDist) {
        minDist = dist;
        nearest = stop;
      }
    }

    if (nearest != null && minDist <= stopRadiusMeters) {
      return (nearest.id, nearest.name);
    }
    return null;
  }
}
