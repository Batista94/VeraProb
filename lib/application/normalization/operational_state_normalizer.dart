import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/shared/geo_math.dart';
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
///
/// Internal pipeline (per ping):
///   Temporal Guard → Debounce Guard → Jump Filter
///   → Smooth + Classify → Enrich → Build State
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

  /// Last processed event timestamp per vehicle (temporal guard — INV-18).
  final Map<String, DateTime> _lastProcessedTimestamp = {};

  final IDateTimeProvider _clock;

  OperationalStateNormalizer({
    this.debounceDuration = const Duration(seconds: 5),
    this.jumpThresholdMeters = 500.0,
    this.degradedThreshold = const Duration(seconds: 120),
    this.signalLostThreshold = const Duration(seconds: 300),
    this.stopRadiusMeters = 100.0,
    this.movingSpeedThreshold = 2.0,
    this.slowTrafficThreshold = 0.5,
    this.stoppedMinDuration = const Duration(seconds: 30),
    this.slowTrafficMinDuration = const Duration(seconds: 15),
    MotionClassifier? motionClassifier,
    IDateTimeProvider? clock,
  }) : _motionClassifier = motionClassifier,
       _clock = clock ?? BrazilDateTimeProvider();

  // ── Public API ────────────────────────────────────────────────────

  /// Process incoming [pings] and return a list of stabilized states.
  ///
  /// When [pings] is empty the normalizer replays degraded states for
  /// every tracked vehicle (useful when polling on a timer).
  /// [knownStops] enriches motion classification with geofence checks.
  /// [now] defaults to system UTC time (via IDateTimeProvider) when null.
  ///
  /// Pipeline per ping:
  ///   _applyTemporalGuard → _applyDebounceGuard → _applyJumpFilter
  ///   → smooth + classify → _resolveRouteAdherenceForPing
  ///   → _enrichNearestStop → _buildOperationalState
  List<VehicleOperationalState> normalize(
    List<VehiclePosition> pings, {
    List<Stop> knownStops = const [],
    DateTime? now,
  }) {
    // INV-6: effectiveNow resolved once — all temporal comparisons use this
    // single immutable reference to prevent clock drift within the batch.
    final effectiveNow = now ?? _clock.nowUtc();
    _ensureClassifier();

    if (pings.isEmpty) {
      return _replayAllDegradedStates(effectiveNow, knownStops);
    }

    final results = <VehicleOperationalState>[];
    for (final ping in pings) {
      final state = _processSinglePing(ping, effectiveNow, knownStops);
      if (state != null) results.add(state);
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

  // ── Orchestration Layer ───────────────────────────────────────────

  /// Replays a degraded state for every tracked vehicle when no pings arrive.
  /// Used for timer-based polling to maintain stream frequency without
  /// introducing false data.
  List<VehicleOperationalState> _replayAllDegradedStates(
    DateTime effectiveNow,
    List<Stop> knownStops,
  ) {
    final results = <VehicleOperationalState>[];
    for (final vehicleId in _cache.keys.toList()) {
      final state = _replayDegradedState(vehicleId, effectiveNow, knownStops);
      results.add(state);
      _cache[vehicleId] = state;
    }
    _cleanStaleStates(effectiveNow);
    return results;
  }

  /// Full pipeline for a single incoming ping.
  ///
  /// Returns the new [VehicleOperationalState] or null when the ping is
  /// suppressed by a guard (stale, debounced, or jump-rejected).
  /// In the latter cases the cached state is already added to the caller's
  /// result list by the guard methods.
  VehicleOperationalState? _processSinglePing(
    VehiclePosition ping,
    DateTime effectiveNow,
    List<Stop> knownStops,
  ) {
    final vehicleId = _resolveVehicleId(ping);
    final cached = _cache[vehicleId];

    // ── Guard Layer (INV-18: Zero-Trust Telemetry) ────────────────
    if (_applyTemporalGuard(vehicleId, ping.timestamp)) {
      return cached; // null if not yet tracked — caller skips null
    }
    if (_applyDebounceGuard(vehicleId, effectiveNow, ping.speed)) {
      return cached;
    }
    final (jumpRejected, jumpDistance) = _applyJumpFilter(vehicleId, ping);
    if (jumpRejected) {
      return _replayDegradedState(vehicleId, effectiveNow, knownStops);
    }

    // ── Smooth + Classify ─────────────────────────────────────────
    final buffer = _rawBuffers.putIfAbsent(vehicleId, () => Queue());
    buffer.add(ping);
    if (buffer.length > 3) buffer.removeFirst();

    final (lat, lng) = _smoother.applySmoothing(buffer);
    final avgSpeed = _smoother.smoothSpeed(buffer);

    final isFirstPing = !_cache.containsKey(vehicleId);
    final motion = _motionClassifier!.classifyMotion(
      vehicleId,
      avgSpeed,
      (lat, lng),
      knownStops,
      effectiveNow,
      previousPosition: cached != null
          ? (cached.latitude, cached.longitude)
          : null,
      previousTimestamp: cached?.lastRawPingAt,
      isFirstPing: isFirstPing,
    );

    // ── Enrich Layer ──────────────────────────────────────────────
    final (
      routeAdherence,
      accuracyGatekeeperActive,
    ) = _resolveRouteAdherenceForPing(
      motion,
      cached,
      lat,
      lng,
      knownStops,
      ping.accuracyMeters,
    );

    // Connectivity analysis — pass previousLastRawPingAt for gap-recovery
    // detection. The resulting state stores ping.timestamp as lastRawPingAt,
    // so the next ping sees gap=0 and is not mis-classified (no recovery loop).
    final conn = _connectivityAnalyzer.classify(
      ping.timestamp,
      effectiveNow,
      previousLastRawPingAt: cached?.lastRawPingAt,
      degradedThreshold: degradedThreshold,
      signalLostThreshold: signalLostThreshold,
    );

    final nearestStop = _enrichNearestStop(motion, lat, lng, knownStops);

    // ── Build State ───────────────────────────────────────────────
    final state = _buildOperationalState(
      ping: ping,
      vehicleId: vehicleId,
      lat: lat,
      lng: lng,
      avgSpeed: avgSpeed,
      motion: motion,
      conn: conn,
      routeAdherence: routeAdherence,
      accuracyGatekeeperActive: accuracyGatekeeperActive,
      nearestStop: nearestStop,
      jumpDistance: jumpDistance,
      cached: cached,
    );

    _cache[vehicleId] = state;
    _lastEmittedAt[vehicleId] = effectiveNow;
    _lastProcessedTimestamp[vehicleId] = ping.timestamp;
    return state;
  }

  // ── Guard Layer (Fail-Fast — INV-18) ─────────────────────────────

  /// Returns true if [pingTimestamp] is stale (equal to or older than the
  /// last processed timestamp for this vehicle).
  ///
  /// Stale events are replayed from cache to maintain stream frequency without
  /// corrupting temporal integrity. INV-18: Zero-Trust Telemetry.
  bool _applyTemporalGuard(String vehicleId, DateTime pingTimestamp) {
    final lastProcessed = _lastProcessedTimestamp[vehicleId];
    if (lastProcessed == null) return false;

    final isStale =
        pingTimestamp.isBefore(lastProcessed) ||
        pingTimestamp.isAtSameMomentAs(lastProcessed);

    if (isStale) {
      debugPrint(
        'REJECTED_STALE_EVENT: vehicleId=$vehicleId, '
        'eventTs=$pingTimestamp, lastProcessed=$lastProcessed',
      );
    }
    return isStale;
  }

  /// Returns true if [effectiveNow] is within the debounce window of the
  /// last emission for this vehicle.
  bool _applyDebounceGuard(
    String vehicleId,
    DateTime effectiveNow,
    double? speed,
  ) {
    final lastEmit = _lastEmittedAt[vehicleId];
    if (lastEmit == null) return false;

    final withinWindow = effectiveNow.difference(lastEmit) < debounceDuration;

    if (withinWindow) {
      debugPrint(
        'REJECTED_DEBOUNCE: vehicleId=$vehicleId, '
        'speed=$speed, duration=${effectiveNow.difference(lastEmit)}',
      );
    }
    return withinWindow;
  }

  /// Returns a record (rejected, jumpDistance) where:
  /// - rejected = true when the ping teleports beyond [jumpThresholdMeters].
  /// - jumpDistance is the distance from the cached position (0 if no cache).
  ///
  /// Pings that pass but are suspiciously far reduce downstream confidence:
  ///   confidence_factor = 1 − (jumpDistance / jumpThresholdMeters).
  (bool rejected, double distance) _applyJumpFilter(
    String vehicleId,
    VehiclePosition ping,
  ) {
    final cached = _cache[vehicleId];
    if (cached == null) return (false, 0.0);

    final distance = GeoMath.haversineMeters(
      // Physical Metric - Double Required
      cached.latitude,
      cached.longitude,
      ping.latitude,
      ping.longitude,
    );

    if (distance > jumpThresholdMeters) {
      debugPrint(
        'REJECTED_JUMP: vehicleId=$vehicleId, '
        'distance=${distance.toStringAsFixed(1)}, velocity_check=FAILED',
      );
      return (true, distance);
    }
    return (false, distance);
  }

  // ── Enrichment Layer ──────────────────────────────────────────────

  /// Resolves route adherence with a stopped-vehicle optimization:
  /// stopped vehicles reuse the cached adherence (no movement = no route change),
  /// avoiding expensive geospatial calculations for stationary vehicles.
  (RouteAdherence, bool) _resolveRouteAdherenceForPing(
    MotionState motion,
    VehicleOperationalState? cached,
    double lat,
    double lng,
    List<Stop> knownStops,
    double? accuracyMeters,
  ) {
    if (motion == MotionState.stopped) {
      return (
        cached?.routeAdherence ?? RouteAdherence.onRoute,
        cached?.accuracyGatekeeperActive ?? false,
      );
    }
    return _evaluateRouteAdherence(lat, lng, knownStops, accuracyMeters);
  }

  /// Returns the nearest stop info when the vehicle is dwelling at a stop.
  /// Returns all-null record for any other motion state or when no stop
  /// is within [stopRadiusMeters].
  ///
  /// Pure function — same input always yields same output.
  ({String? id, String? name, double? distance}) _enrichNearestStop(
    MotionState motion,
    double lat,
    double lng,
    List<Stop> knownStops,
  ) {
    if (motion != MotionState.dwellingAtStop || knownStops.isEmpty) {
      return (id: null, name: null, distance: null);
    }

    for (final stop in knownStops) {
      final d = GeoMath.haversineMeters(
        // Physical Metric - Double Required
        lat,
        lng,
        stop.latitude,
        stop.longitude,
      );
      if (d <= stopRadiusMeters) {
        return (id: stop.id, name: stop.name, distance: d);
      }
    }
    return (id: null, name: null, distance: null);
  }

  /// Computes the final confidence score for a state snapshot.
  ///
  /// Combines connectivity quality with a spatial penalty for near-threshold
  /// jumps: confidence = conn.confidence × (1 − jumpDistance / jumpThreshold).
  ///
  /// Pure function — same input always yields same output.
  double _computeConfidence(
    ConnectivityState conn,
    double jumpDistance, // Physical Metric - Double Required
  ) {
    return conn.confidence * (1.0 - jumpDistance / jumpThresholdMeters);
  }

  /// Resolves [stateChangedAt] for the new state.
  ///
  /// INV-6 (Forensic Immutability): stateChangedAt ONLY advances when
  /// [motionState] transitions. Connectivity-only changes MUST NOT contaminate
  /// the movement duration evidence recorded here.
  ///
  /// Pure function — same input always yields same output.
  DateTime _resolveStateChangedAt({
    required MotionState? prevMotion,
    required MotionState newMotion,
    required DateTime pingTimestamp,
    required DateTime? prevStateChangedAt,
  }) {
    final hasMotionTransitioned = prevMotion == null || prevMotion != newMotion;
    return hasMotionTransitioned ? pingTimestamp : prevStateChangedAt!;
  }

  // ── State Construction ────────────────────────────────────────────

  /// Assembles the immutable [VehicleOperationalState] from all pipeline
  /// outputs. This is the only place where the DTO is constructed for live
  /// pings — preserving a single construction site for auditability.
  VehicleOperationalState _buildOperationalState({
    required VehiclePosition ping,
    required String vehicleId,
    required double lat,
    required double lng,
    required double avgSpeed,
    required MotionState motion,
    required ConnectivityState conn,
    required RouteAdherence routeAdherence,
    required bool accuracyGatekeeperActive,
    required ({String? id, String? name, double? distance}) nearestStop,
    required double jumpDistance, // Physical Metric - Double Required
    required VehicleOperationalState? cached,
  }) {
    return VehicleOperationalState(
      vehicleId: vehicleId,
      tripId: ping.tripId,
      latitude: lat,
      longitude: lng,
      heading: ping.heading,
      smoothedSpeed: avgSpeed,
      rawSpeed: ping.speed ?? 0.0, // Physical Metric - Double Required (INV-9)

      motionState: motion,
      connectivityState: conn,
      routeAdherence: routeAdherence,
      accuracyGatekeeperActive: accuracyGatekeeperActive,
      lastRawPingAt: ping.timestamp,
      stateChangedAt: _resolveStateChangedAt(
        prevMotion: cached?.motionState,
        newMotion: motion,
        pingTimestamp: ping.timestamp,
        prevStateChangedAt: cached?.stateChangedAt,
      ),
      nearestStopId: nearestStop.id,
      nearestStopName: nearestStop.name,
      distanceToRoute: nearestStop.distance,
      confidence: _computeConfidence(conn, jumpDistance),
      routeName: ping.routeName,
      vehiclePlate: ping.vehiclePlate,
      source: ping.source,
    );
  }

  // ── Private Helpers ───────────────────────────────────────────────

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
      previousPosition: (previous.latitude, previous.longitude),
      previousTimestamp: previous.lastRawPingAt,
      isFirstPing: false, // Replay is never first ping
    );

    // stateChangedAt ONLY advances when motionState actually changes —
    // connectivity changes must NOT contaminate movement duration evidence.
    final hasMotionChanged = previous.motionState != motion;

    return previous.copyWith(
      connectivityState: conn,
      motionState: motion,
      confidence: conn.confidence,
      stateChangedAt: hasMotionChanged ? now : previous.stateChangedAt,
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
      rawSpeed: 0, // Physical Metric - Double Required
      motionState: MotionState.moving,
      connectivityState: conn,
      routeAdherence: RouteAdherence.onRoute,
      accuracyGatekeeperActive: false,
      lastRawPingAt: now,
      stateChangedAt: now,
      confidence: conn.confidence,
      source: 'normalizer',
    );
  }

  (RouteAdherence, bool) _evaluateRouteAdherence(
    double lat,
    double lng,
    List<Stop> knownStops, // Physical Metric - Double Required
    double? accuracyMeters, // Physical Metric - Double Required
  ) {
    // Accuracy gatekeeper - prevent false penalties from low-quality GPS
    if (accuracyMeters != null && accuracyMeters > 100) {
      return (
        RouteAdherence.onRoute,
        true,
      ); // Benefit of doubt for degraded GPS
    }

    if (knownStops.isEmpty) return (RouteAdherence.onRoute, false);

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

    if (minDist > 100) return (RouteAdherence.offRoute, false);
    if (minDist > 80) return (RouteAdherence.minorDeviation, false);
    return (RouteAdherence.onRoute, false);
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
      _lastProcessedTimestamp.remove(key);
      _motionClassifier?.removeKey(key);
    }
  }
}
