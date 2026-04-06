import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';

/// Represents the global operational status of the fleet.
/// Pure data contract used for rendering the Fleet Status sidebar/panels.
class FleetStatusProjection {
  final List<VehicleOperationalState> activeVehicles;
  final List<VehicleOperationalState> delayedVehicles;
  final List<VehicleOperationalState> offRouteVehicles;
  final List<VehicleOperationalState> signalLostVehicles;
  final List<VehicleOperationalState> allFilteredVehicles;

  const FleetStatusProjection({
    this.activeVehicles = const [],
    this.delayedVehicles = const [],
    this.offRouteVehicles = const [],
    this.signalLostVehicles = const [],
    this.allFilteredVehicles = const [],
  });

  /// Total number of vehicles currently tracked
  int get totalActive => activeVehicles.length;

  /// Number of vehicles requiring immediate operator attention
  int get totalIssues =>
      delayedVehicles.length +
      offRouteVehicles.length +
      signalLostVehicles.length;

  FleetStatusProjection copyWith({
    List<VehicleOperationalState>? activeVehicles,
    List<VehicleOperationalState>? delayedVehicles,
    List<VehicleOperationalState>? offRouteVehicles,
    List<VehicleOperationalState>? signalLostVehicles,
    List<VehicleOperationalState>? allFilteredVehicles,
  }) {
    return FleetStatusProjection(
      activeVehicles: activeVehicles ?? this.activeVehicles,
      delayedVehicles: delayedVehicles ?? this.delayedVehicles,
      offRouteVehicles: offRouteVehicles ?? this.offRouteVehicles,
      signalLostVehicles: signalLostVehicles ?? this.signalLostVehicles,
      allFilteredVehicles: allFilteredVehicles ?? this.allFilteredVehicles,
    );
  }
}
