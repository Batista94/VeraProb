import 'package:equatable/equatable.dart';
import 'motion_state.dart';
import 'connectivity_state.dart';
import 'route_adherence.dart';

/// The stabilized operational view of a vehicle at a point in time.
///
/// This is the OUTPUT of the [OperationalStateNormalizer]. It replaces
/// raw [VehiclePosition] as the entity consumed by the Situation Engine
/// and the UI layer.
///
/// Key differences from [VehiclePosition]:
/// - Position is spatially smoothed (no GPS jitter).
/// - Speed is averaged over the last 3 readings.
/// - Operational classification ([motionState], [connectivityState],
///   [routeAdherence]) is pre-computed — the UI never interprets GPS.
class VehicleOperationalState extends Equatable {
  /// Unique vehicle identifier for this state snapshot.
  final String vehicleId;

  /// The trip this vehicle is currently executing.
  final String tripId;

  // ── Stabilized position (post-smoothing) ──────────────
  final double latitude;
  final double longitude;
  final double? heading;

  /// Speed in km/h, averaged over the last 3 raw readings.
  final double smoothedSpeed;

  // ── Operational classifications ────────────────────────
  final MotionState motionState;
  final ConnectivityState connectivityState;
  final RouteAdherence routeAdherence;

  // ── Metadata ───────────────────────────────────────────

  /// Timestamp of the last raw GPS ping received from the device.
  final DateTime lastRawPingAt;

  /// When [motionState] last transitioned (e.g. moving → stopped).
  final DateTime stateChangedAt;

  /// Populated when [motionState] == [MotionState.dwellingAtStop].
  final String? nearestStopId;
  final String? nearestStopName;

  /// Perpendicular distance to the GTFS route shape (metres).
  /// Null when shapes are unavailable.
  final double? distanceToRoute;

  /// Overall confidence in this state snapshot (0.0–1.0).
  /// Derived from [connectivityState] but can be further reduced
  /// by jump-filtered or degraded readings.
  final double confidence;

  /// Display fields carried forward from the raw position.
  final String? routeName;
  final String? vehiclePlate;
  final String source;

  const VehicleOperationalState({
    required this.vehicleId,
    required this.tripId,
    required this.latitude,
    required this.longitude,
    this.heading,
    required this.smoothedSpeed,
    required this.motionState,
    required this.connectivityState,
    this.routeAdherence = RouteAdherence.onRoute,
    required this.lastRawPingAt,
    required this.stateChangedAt,
    this.nearestStopId,
    this.nearestStopName,
    this.distanceToRoute,
    required this.confidence,
    this.routeName,
    this.vehiclePlate,
    required this.source,
  });

  /// Whether this vehicle needs operator attention based on its
  /// operational state alone (before the Situation Engine runs).
  bool get requiresAttention =>
      connectivityState == ConnectivityState.signalLost ||
      routeAdherence == RouteAdherence.offRoute;

  VehicleOperationalState copyWith({
    String? vehicleId,
    String? tripId,
    double? latitude,
    double? longitude,
    double? heading,
    double? smoothedSpeed,
    MotionState? motionState,
    ConnectivityState? connectivityState,
    RouteAdherence? routeAdherence,
    DateTime? lastRawPingAt,
    DateTime? stateChangedAt,
    String? nearestStopId,
    String? nearestStopName,
    double? distanceToRoute,
    double? confidence,
    String? routeName,
    String? vehiclePlate,
    String? source,
  }) {
    return VehicleOperationalState(
      vehicleId: vehicleId ?? this.vehicleId,
      tripId: tripId ?? this.tripId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      heading: heading ?? this.heading,
      smoothedSpeed: smoothedSpeed ?? this.smoothedSpeed,
      motionState: motionState ?? this.motionState,
      connectivityState: connectivityState ?? this.connectivityState,
      routeAdherence: routeAdherence ?? this.routeAdherence,
      lastRawPingAt: lastRawPingAt ?? this.lastRawPingAt,
      stateChangedAt: stateChangedAt ?? this.stateChangedAt,
      nearestStopId: nearestStopId ?? this.nearestStopId,
      nearestStopName: nearestStopName ?? this.nearestStopName,
      distanceToRoute: distanceToRoute ?? this.distanceToRoute,
      confidence: confidence ?? this.confidence,
      routeName: routeName ?? this.routeName,
      vehiclePlate: vehiclePlate ?? this.vehiclePlate,
      source: source ?? this.source,
    );
  }

  @override
  List<Object?> get props => [
    vehicleId,
    tripId,
    latitude,
    longitude,
    heading,
    smoothedSpeed,
    motionState,
    connectivityState,
    routeAdherence,
    lastRawPingAt,
    stateChangedAt,
    nearestStopId,
    distanceToRoute,
    confidence,
  ];
}
