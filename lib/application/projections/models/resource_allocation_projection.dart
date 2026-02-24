/// Represents a combined view of a driver and their assigned vehicle/route.
class ResourceAllocationNode {
  final String driverId;
  final String driverName;
  final String? assignedVehicleId;
  final String? assignedVehiclePlate;
  final String? assignedTripId;
  final String? assignedRouteName;

  /// True if the driver is assigned but no vehicle is pinging, or mismatch detected.
  final bool hasConflict;

  const ResourceAllocationNode({
    required this.driverId,
    required this.driverName,
    this.assignedVehicleId,
    this.assignedVehiclePlate,
    this.assignedTripId,
    this.assignedRouteName,
    this.hasConflict = false,
  });

  bool get isAssigned => assignedVehicleId != null;
}

/// The pure data contract for the Resource Management view.
class ResourceAllocationProjection {
  final List<ResourceAllocationNode> nodes;

  const ResourceAllocationProjection({this.nodes = const []});

  int get totalDrivers => nodes.length;
  int get activeAssignments => nodes.where((n) => n.isAssigned).length;
  int get totalConflicts => nodes.where((n) => n.hasConflict).length;

  ResourceAllocationProjection copyWith({List<ResourceAllocationNode>? nodes}) {
    return ResourceAllocationProjection(nodes: nodes ?? this.nodes);
  }
}
