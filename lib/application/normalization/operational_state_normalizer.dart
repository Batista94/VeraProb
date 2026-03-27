import 'dart:collection';
import '../../core/utils/geo_math.dart';
import '../../domain/entities/vehicle_position.dart';
import '../../domain/entities/stop.dart';
import 'models/vehicle_operational_state.dart';
import 'models/motion_state.dart';
import 'models/connectivity_state.dart';
import 'models/route_adherence.dart';

/// Converts raw GPS telemetry into stabilized operational state.
///
/// This is the critical layer between [IOperationalDataProvider] and the
/// [SituationEngine]. It ensures the UI and intelligence layers never
/// process raw, noisy GPS coordinates.
///
/// Capabilities:
/// - **Temporal debounce**: Max 1 update / vehicle / [debounceDuration].
/// - **Spatial smoothing**: Weighted average of last 3 positions.
/// - **Jump detection**: Discards impossible teleports (> [jumpThresholdMeters] in < 5 s).
/// - **Signal-loss FSM**: `healthy` → `degraded` → `signalLost`.
/// - **Stop geofencing**: Detects `dwellingAtStop` within [stopRadiusMeters] of known stops.
/// - **Route adherence**: Placeholder for GTFS shape distance (future).
class OperationalStateNormalizer {
  // ── Configuration ─────────────────────────────────────
  final Duration debounceDuration;
  final double jumpThresholdMeters;
  final Duration degradedThreshold;
  final Duration signalLostThreshold;
  final double stopRadiusMeters;
  final double movingSpeedThreshold; // km/h
  final double slowTrafficThreshold; // km/h
  final Duration stoppedMinDuration;
  final Duration slowTrafficMinDuration;
  static const List<double> _smoothingWeights = [0.15, 0.25, 0.60];

  OperationalStateNormalizer({
    this.debounceDuration = const Duration(seconds: 5),
    this.jumpThresholdMeters = 500.0,
    this.degradedThreshold = const Duration(seconds: 30),
    this.signalLostThreshold = const Duration(seconds: 90),
    this.stopRadiusMeters = 50.0,
    this.movingSpeedThreshold = 8.0,
    this.slowTrafficThreshold = 2.0,
    this.stoppedMinDuration = const Duration(seconds: 15),
    this.slowTrafficMinDuration = const Duration(seconds: 30),
  });

  // ── Per-vehicle state buffers ─────────────────────────
  /// Circular buffer of the last 3 raw positions per vehicle.
  final Map<String, Queue<VehiclePosition>> _positionBuffers = {};

  /// Last emitted timestamp per vehicle (for debounce).
  final Map<String, DateTime> _lastEmittedAt = {};

  /// Last emitted operational state per vehicle.
  final Map<String, VehicleOperationalState> _lastStates = {};

  /// When each vehicle first entered a low-speed state.
  final Map<String, DateTime> _lowSpeedSince = {};

  // ── Public API ────────────────────────────────────────

  /// Process a batch of raw positions and return stabilized states.
  ///
  /// [rawPositions] — the latest GPS pings from the data adapter.
  /// [knownStops]   — all known transit stops for geofencing.
  /// [now]          — injectable clock for testability.
  List<VehicleOperationalState> normalize(
    List<VehiclePosition> rawPositions, {
    List<Stop> knownStops = const [],
    DateTime? now,
  }) {
    final currentTime = now ?? DateTime.now().toUtc();
    final results = <VehicleOperationalState>[];

    // Index known stops for fast geofencing lookup
    final stopsLookup = knownStops;

    // Track which vehicles sent a ping this cycle
    final activeVehicleIds = <String>{};

    for (final raw in rawPositions) {
      final vehicleId = raw.tripId; // tripId used as vehicle key
      activeVehicleIds.add(vehicleId);

      // ── 1. Debounce ───────────────────────────────────
      final lastEmit = _lastEmittedAt[vehicleId];
      if (lastEmit != null &&
          currentTime.difference(lastEmit) < debounceDuration) {
        // Too soon — re-emit the last known state if available
        final cached = _lastStates[vehicleId];
        if (cached != null) results.add(cached);
        continue;
      }

      // ── 2. Buffer management ──────────────────────────
      _positionBuffers.putIfAbsent(vehicleId, () => Queue<VehiclePosition>());
      final buffer = _positionBuffers[vehicleId]!;

      // ── 3. Jump detection ─────────────────────────────
      if (buffer.isNotEmpty) {
        final prev = buffer.last;
        final distM = GeoMath.haversineMeters(
          prev.latitude,
          prev.longitude,
          raw.latitude,
          raw.longitude,
        );
        final dtSec = raw.timestamp.difference(prev.timestamp).inSeconds.abs();
        if (distM > jumpThresholdMeters && dtSec < 5) {
          // Impossible jump — discard this ping, re-emit cached state
          final cached = _lastStates[vehicleId];
          if (cached != null) results.add(cached);
          continue;
        }
      }

      // Add to buffer (keep max 3)
      buffer.addLast(raw);
      while (buffer.length > 3) {
        buffer.removeFirst();
      }

      // ── 4. Spatial smoothing ──────────────────────────
      final smoothed = _applySmoothing(buffer);
      final smoothedSpeed = _smoothSpeed(buffer);

      // ── 5. Motion state classification ────────────────
      final motionState = _classifyMotion(
        vehicleId,
        smoothedSpeed,
        smoothed,
        stopsLookup,
        currentTime,
      );

      // ── 6. Connectivity state ─────────────────────────
      final connectivity = _classifyConnectivity(raw.timestamp, currentTime);

      // ── 7. Stop geofencing ────────────────────────────
      String? nearestStopId;
      String? nearestStopName;
      if (motionState == MotionState.dwellingAtStop) {
        final nearest = _findNearestStop(smoothed.$1, smoothed.$2, stopsLookup);
        nearestStopId = nearest?.$1;
        nearestStopName = nearest?.$2;
      }

      // ── 8. Build stabilized state ─────────────────────
      final previousState = _lastStates[vehicleId];
      final stateChanged =
          previousState == null || previousState.motionState != motionState;

      final state = VehicleOperationalState(
        vehicleId: vehicleId,
        tripId: raw.tripId,
        latitude: smoothed.$1,
        longitude: smoothed.$2,
        heading: raw.heading,
        smoothedSpeed: smoothedSpeed,
        motionState: motionState,
        connectivityState: connectivity,
        routeAdherence: RouteAdherence.onRoute, // Placeholder until GTFS shapes
        lastRawPingAt: raw.timestamp,
        stateChangedAt: stateChanged
            ? currentTime
            : (previousState.stateChangedAt),
        nearestStopId: nearestStopId,
        nearestStopName: nearestStopName,
        distanceToRoute: null, // Future: GTFS shape distance
        confidence: connectivity.confidence,
        routeName: raw.routeName,
        vehiclePlate: raw.vehiclePlate,
        source: raw.source,
      );

      _lastStates[vehicleId] = state;
      _lastEmittedAt[vehicleId] = currentTime;
      results.add(state);
    }

    // ── 9. Handle vehicles with NO ping this cycle ──────
    for (final entry in _lastStates.entries) {
      if (!activeVehicleIds.contains(entry.key)) {
        final stale = entry.value;
        final connectivity = _classifyConnectivity(
          stale.lastRawPingAt,
          currentTime,
        );
        // Re-emit with updated connectivity (may transition to signalLost)
        final updated = stale.copyWith(
          connectivityState: connectivity,
          confidence: connectivity.confidence,
        );
        _lastStates[entry.key] = updated;
        results.add(updated);
      }
    }

    return results;
  }

  /// Clear all internal state (useful for testing or mode switching).
  void reset() {
    _positionBuffers.clear();
    _lastEmittedAt.clear();
    _lastStates.clear();
    _lowSpeedSince.clear();
  }

  // ── Private: Smoothing ────────────────────────────────

  /// Returns (latitude, longitude) as a weighted average of the buffer.
  (double, double) _applySmoothing(Queue<VehiclePosition> buffer) {
    if (buffer.length == 1) {
      return (buffer.first.latitude, buffer.first.longitude);
    }

    final positions = buffer.toList();
    // Use tail of weights matching buffer size
    final weights = _smoothingWeights.sublist(
      _smoothingWeights.length - positions.length,
    );
    final weightSum = weights.reduce((a, b) => a + b);

    double lat = 0, lng = 0;
    for (int i = 0; i < positions.length; i++) {
      final w = weights[i] / weightSum;
      lat += positions[i].latitude * w;
      lng += positions[i].longitude * w;
    }
    return (lat, lng);
  }

  /// Returns smoothed speed in km/h as weighted average.
  double _smoothSpeed(Queue<VehiclePosition> buffer) {
    final positions = buffer.toList();
    final weights = _smoothingWeights.sublist(
      _smoothingWeights.length - positions.length,
    );
    final weightSum = weights.reduce((a, b) => a + b);

    double speed = 0;
    for (int i = 0; i < positions.length; i++) {
      final w = weights[i] / weightSum;
      speed += (positions[i].speed ?? 0.0) * w;
    }
    return speed;
  }

  // ── Private: Classification ───────────────────────────

  MotionState _classifyMotion(
    String vehicleId,
    double smoothedSpeed,
    (double, double) position,
    List<Stop> stops,
    DateTime now,
  ) {
    if (smoothedSpeed > movingSpeedThreshold) {
      _lowSpeedSince.remove(vehicleId);
      return MotionState.moving;
    }

    // Vehicle is slow or stopped
    _lowSpeedSince.putIfAbsent(vehicleId, () => now);
    final lowSpeedDuration = now.difference(_lowSpeedSince[vehicleId]!);

    if (smoothedSpeed <= slowTrafficThreshold) {
      // Potential stop
      if (lowSpeedDuration >= stoppedMinDuration) {
        // Check if near a known stop
        final nearStop = _findNearestStop(position.$1, position.$2, stops);
        if (nearStop != null) {
          return MotionState.dwellingAtStop;
        }
        return MotionState.stopped;
      }
      // Not long enough to classify as stopped yet
      return MotionState.moving;
    }

    // Between slowTrafficThreshold and movingSpeedThreshold
    if (lowSpeedDuration >= slowTrafficMinDuration) {
      return MotionState.slowTraffic;
    }
    return MotionState.moving;
  }

  ConnectivityState _classifyConnectivity(DateTime lastPing, DateTime now) {
    final age = now.difference(lastPing);
    if (age <= degradedThreshold) return ConnectivityState.healthy;
    if (age <= signalLostThreshold) return ConnectivityState.degraded;
    return ConnectivityState.signalLost;
  }

  // ── Private: Geofencing ───────────────────────────────

  /// Returns (stopId, stopName) if a stop is within [stopRadiusMeters],
  /// or null if no stop is nearby.
  (String, String)? _findNearestStop(double lat, double lng, List<Stop> stops) {
    double minDist = double.infinity;
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
