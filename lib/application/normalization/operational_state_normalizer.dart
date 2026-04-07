import 'dart:collection';
import 'package:veraprob/core/utils/geo_math.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'package:veraprob/domain/entities/stop.dart';
import 'models/vehicle_operational_state.dart';
import 'models/motion_state.dart';
import 'models/connectivity_state.dart';
import 'models/route_adherence.dart';
import 'spatial_smoother.dart';
import 'motion_classifier.dart';
import 'connectivity_analyzer.dart';

/// Orchestrator that transforms raw GPS pings into stabilized
/// [VehicleOperationalState] snapshots.
///
/// Responsibilities:
/// - Debounce: suppresses updates within [debounceDuration].
/// - Jump filtering: rejects impossible teleportation.
/// - Spatial smoothing: 3-sample weighted average via [SpatialSmoother].
/// - Motion classification: delegates to [MotionClassifier].
/// - Connectivity analysis: delegates to [ConnectivityAnalyzer].
class OperationalStateNormalizer {
  final Duration debounceDuration;
  final double jumpThresholdMeters; // Physical Metric - Double Required
  final Duration degradedThreshold;
  final Duration signalLostThreshold;
  final double stopRadiusMeters; // Physical Metric - Double Required
  final double movingSpeedThreshold; // Physical Metric - Double Required
  final double slowTrafficThreshold; // Physical Metric - Double Required
  final Duration stoppedMinDuration;
  final Duration slowTrafficMinDuration;

  final SpatialSmoother _smoother = const SpatialSmoother();
  MotionClassifier? _motionClassifier;
  final ConnectivityAnalyzer _connectivityAnalyzer =
      const ConnectivityAnalyzer();

  /// Buffer per vehicle: up to 3 most recent pings.
  final Map<String, Queue<VehiclePosition>> _rawBuffers = {};

  /// Last emitted [VehicleOperationalState] per vehicle (for debounce / missing ping replay).
  final Map<String, VehicleOperationalState> _cache = {};

  /// Timestamp of last emitted state per vehicle (debounce guard).
  final Map<String, DateTime> _lastEmittedAt = {};

  OperationalStateNormalizer({
    this.debounceDuration = const Duration(seconds: 5),
    this.jumpThresholdMeters = 500.0,
    this.degradedThreshold = const Duration(seconds: 30),
    this.signalLostThreshold = const Duration(seconds: 90),
    this.stopRadiusMeters = 50.0,
    this.movingSpeedThreshold = 8.0,
    this.slowTrafficThreshold = 2.0,
    this.stoppedMinDuration = const Duration(seconds: 15),
    this.slowTrafficMinDuration = const Duration(seconds: 15),
  });

  /// Process incoming [pings] and return a list of stabilized states.
  ///
  /// When [pings] is empty the normalizer replays degraded states for
  /// every tracked vehicle (useful when polling on a timer).
  /// [knownStops] enriches motion classification with geofence checks.
  /// [now] defaults to `DateTime.now().toUtc()` when null.
  List<VehicleOperationalState> normalize(
    List<VehiclePosition> pings, {
    List<Stop> knownStops = const [],
    DateTime? now,
  }) {
    final effectiveNow = now ?? DateTime.now().toUtc();

    _ensureClassifier();

    final results = <VehicleOperationalState>[];

    if (pings.isEmpty) {
      // Replay degraded states for all tracked vehicles
      for (final vehicleId in _cache.keys.toList()) {
        final state = _replayDegradedState(vehicleId, effectiveNow, knownStops);
        results.add(state);
        _cache[vehicleId] = state;
      }
      _cleanStaleStates(effectiveNow);
      return results;
    }

    for (final ping in pings) {
      final vehicleId = _resolveVehicleId(ping);
      final buffer = _rawBuffers.putIfAbsent(vehicleId, () => Queue());

      // Debounce: skip if within debounce window
      final cached = _cache[vehicleId];
      final lastEmit = _lastEmittedAt[vehicleId];
      if (lastEmit != null &&
          effectiveNow.difference(lastEmit) < debounceDuration) {
        if (cached != null) results.add(cached);
        continue;
      }

      // Jump filter — also records distance for spatial-confidence scoring.
      // Pings that pass the filter but are suspiciously far reduce confidence
      // proportionally: confidence_factor = 1 − (distance / jumpThresholdMeters).
      double jumpDistance = 0; // Physical Metric - Double Required
      if (cached != null) {
        final distance = GeoMath.haversineMeters(
          cached.latitude,
          cached.longitude,
          ping.latitude,
          ping.longitude,
        );
        if (distance > jumpThresholdMeters) {
          // Reject the jump; replay cached degraded state
          results.add(
            _replayDegradedState(vehicleId, effectiveNow, knownStops),
          );
          continue;
        }
        jumpDistance = distance;
      }

      // Append to buffer (max 3)
      buffer.add(ping);
      if (buffer.length > 3) buffer.removeFirst();

      // Spatial smoothing & speed averaging
      final (lat, lng) = _smoother.applySmoothing(buffer);
      final avgSpeed = _smoother.smoothSpeed(buffer);

      // Motion classification
      final motion = _motionClassifier!.classifyMotion(
        vehicleId,
        avgSpeed,
        (lat, lng),
        knownStops,
        effectiveNow,
      );

      // Connectivity analysis — pass previousLastRawPingAt for gap-recovery detection.
      // The resulting state stores ping.timestamp as lastRawPingAt, so the next ping
      // sees gap=0 and is not mis-classified (no recovery loop).
      final conn = _connectivityAnalyzer.classify(
        ping.timestamp,
        effectiveNow,
        previousLastRawPingAt: cached?.lastRawPingAt,
        degradedThreshold: degradedThreshold,
        signalLostThreshold: signalLostThreshold,
      );

      var (nearestStopId, nearestStopName) = (null as String?, null as String?);
      double? distanceToRoute;

      if (knownStops.isNotEmpty && motion == MotionState.dwellingAtStop) {
        nearStop:
        for (final stop in knownStops) {
          final d = GeoMath.haversineMeters(
            lat,
            lng,
            stop.latitude,
            stop.longitude,
          );
          if (d <= stopRadiusMeters) {
            nearestStopId = stop.id;
            nearestStopName = stop.name;
            distanceToRoute = d;
            break nearStop;
          }
        }
      }

      // Route adherence (requires knownStops)
      final routeAdherence = _evaluateRouteAdherence(lat, lng, knownStops);

      final state = VehicleOperationalState(
        vehicleId: vehicleId,
        tripId: ping.tripId,
        latitude: lat,
        longitude: lng,
        heading: ping.heading,
        smoothedSpeed: avgSpeed,
        motionState: motion,
        connectivityState: conn,
        routeAdherence: routeAdherence,
        lastRawPingAt: ping.timestamp,
        stateChangedAt: effectiveNow,
        nearestStopId: nearestStopId,
        nearestStopName: nearestStopName,
        distanceToRoute: distanceToRoute,
        confidence:
            conn.confidence * (1.0 - jumpDistance / jumpThresholdMeters),
        routeName: ping.routeName,
        vehiclePlate: ping.vehiclePlate,
        source: ping.source,
      );

      _cache[vehicleId] = state;
      _lastEmittedAt[vehicleId] = effectiveNow;
      results.add(state);
    }

    _cleanStaleStates(effectiveNow);
    return results;
  }

  /// Clear all internal buffers and cached states.
  void reset() {
    _rawBuffers.clear();
    _cache.clear();
    _lastEmittedAt.clear();
    _motionClassifier?.reset();
  }

  // ── Private helpers ──────────────────────────────────────────────

  String _resolveVehicleId(VehiclePosition ping) {
    return ping.vehiclePlate?.isNotEmpty == true
        ? ping.vehiclePlate!
        : ping.tripId;
  }

  VehicleOperationalState _replayDegradedState(
    String vehicleId,
    DateTime now,
    List<Stop> knownStops,
  ) {
    final previous = _cache[vehicleId];
    if (previous == null) return _emptyState(vehicleId, now);

    final conn = _connectivityAnalyzer.classify(
      previous.lastRawPingAt,
      now,
      degradedThreshold: degradedThreshold,
      signalLostThreshold: signalLostThreshold,
    );

    // Advance the motion timer even without a new ping: the low-speed clock
    // in MotionClassifier keeps ticking, so a vehicle stopped before the gap
    // is correctly promoted to MotionState.stopped on replay.
    final motion = _motionClassifier!.classifyMotion(
      vehicleId,
      previous.smoothedSpeed,
      (previous.latitude, previous.longitude),
      knownStops,
      now,
    );

    return previous.copyWith(
      connectivityState: conn,
      motionState: motion,
      confidence: conn.confidence,
      stateChangedAt: now,
    );
  }

  VehicleOperationalState _emptyState(String vehicleId, DateTime now) {
    const conn = ConnectivityState.signalLost;
    return VehicleOperationalState(
      vehicleId: vehicleId,
      tripId: '',
      latitude: 0,
      longitude: 0,
      smoothedSpeed: 0,
      motionState: MotionState.moving,
      connectivityState: conn,
      lastRawPingAt: now,
      stateChangedAt: now,
      confidence: conn.confidence,
      source: 'normalizer',
    );
  }

  RouteAdherence _evaluateRouteAdherence(
    double lat,
    double lng,
    List<Stop> knownStops, // Physical Metric - Double Required
  ) {
    if (knownStops.isEmpty) return RouteAdherence.onRoute;

    double minDist = double.infinity; // Physical Metric - Double Required
    for (final stop in knownStops) {
      final d = GeoMath.haversineMeters(
        lat,
        lng,
        stop.latitude,
        stop.longitude,
      );
      if (d < minDist) minDist = d;
    }

    if (minDist > 200) return RouteAdherence.offRoute;
    if (minDist > 80) return RouteAdherence.minorDeviation;
    return RouteAdherence.onRoute;
  }

  void _ensureClassifier() {
    _motionClassifier ??= MotionClassifier(
      movingSpeedThreshold: movingSpeedThreshold,
      slowTrafficThreshold: slowTrafficThreshold,
      stoppedMinDuration: stoppedMinDuration,
      slowTrafficMinDuration: slowTrafficMinDuration,
      stopRadiusMeters: stopRadiusMeters,
    );
  }

  void _cleanStaleStates(DateTime now) {
    final toRemove = <String>[];
    for (final entry in _cache.entries) {
      final age = now.difference(entry.value.lastRawPingAt);
      if (age > const Duration(minutes: 30)) {
        toRemove.add(entry.key);
      }
    }
    for (final key in toRemove) {
      _rawBuffers.remove(key);
      _cache.remove(key);
      _lastEmittedAt.remove(key);
      _motionClassifier?.removeKey(key);
    }
  }
}
