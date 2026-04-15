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
  final double latitude; // Physical Metric - Double Required
  final double longitude; // Physical Metric - Double Required
  final double? heading; // Physical Metric - Double Required

  /// Speed in km/h, averaged over the last 3 raw readings.
  final double smoothedSpeed; // Physical Metric - Double Required

  /// Raw speed in km/h as reported by the device (before smoothing).
  /// Preserved for forensic evidence (INV-9 Evidence Sealing).
  /// NOT included in equality comparison to prevent UI flicker from GPS noise.
  final double rawSpeed; // Physical Metric - Double Required

  // ── Operational classifications ────────────────────────
  final MotionState motionState;
  final ConnectivityState connectivityState;
  final RouteAdherence routeAdherence;
  final bool accuracyGatekeeperActive; // Physical Metric - Boolean Required.

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
  final double? distanceToRoute; // Physical Metric - Double Required

  /// Overall confidence in this state snapshot (0.0–1.0).
  /// Derived from [connectivityState] but can be further reduced
  /// by jump-filtered or degraded readings.
  final double confidence; // Physical Metric - Double Required

  /// Horizontal GPS accuracy in metres reported by the device.
  /// Null = unknown (quality filter treats as trusted).
  final double? accuracyMeters; // Physical Metric - Double Required

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
    required this.rawSpeed,

    required this.motionState,
    required this.connectivityState,
    this.routeAdherence = RouteAdherence.onRoute,
    this.accuracyGatekeeperActive = false,
    required this.lastRawPingAt,
    required this.stateChangedAt,
    this.nearestStopId,
    this.nearestStopName,
    this.distanceToRoute,
    required this.confidence,
    this.accuracyMeters,
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
    double? latitude, // Physical Metric - Double Required
    double? longitude, // Physical Metric - Double Required
    double? heading, // Physical Metric - Double Required
    double? rawSpeed, // Physical Metric - Double Required

    double? smoothedSpeed, // Physical Metric - Double Required
    MotionState? motionState,
    ConnectivityState? connectivityState,
    RouteAdherence? routeAdherence,
    bool? accuracyGatekeeperActive,
    DateTime? lastRawPingAt,
    DateTime? stateChangedAt,
    String? nearestStopId,
    String? nearestStopName,
    double? distanceToRoute, // Physical Metric - Double Required
    double? confidence, // Physical Metric - Double Required
    double? accuracyMeters, // Physical Metric - Double Required
    String? routeName,
    String? vehiclePlate,
    String? source,
  }) {
    return VehicleOperationalState(
      vehicleId: vehicleId ?? this.vehicleId,
      tripId: tripId ?? this.tripId,
      latitude: latitude ?? this.latitude,
      rawSpeed: rawSpeed ?? this.rawSpeed,

      longitude: longitude ?? this.longitude,
      heading: heading ?? this.heading,
      smoothedSpeed: smoothedSpeed ?? this.smoothedSpeed,
      motionState: motionState ?? this.motionState,
      connectivityState: connectivityState ?? this.connectivityState,
      routeAdherence: routeAdherence ?? this.routeAdherence,
      accuracyGatekeeperActive:
          accuracyGatekeeperActive ?? this.accuracyGatekeeperActive,
      lastRawPingAt: lastRawPingAt ?? this.lastRawPingAt,
      stateChangedAt: stateChangedAt ?? this.stateChangedAt,
      nearestStopId: nearestStopId ?? this.nearestStopId,
      nearestStopName: nearestStopName ?? this.nearestStopName,
      distanceToRoute: distanceToRoute ?? this.distanceToRoute,
      confidence: confidence ?? this.confidence,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
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
    nearestStopId,
    distanceToRoute,
    confidence,
    accuracyMeters,
    accuracyGatekeeperActive,
  ];
}
