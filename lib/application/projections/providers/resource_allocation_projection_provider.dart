import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/application/projections/models/resource_allocation_projection.dart';

// We need a dummy driver source here since we don't have a dedicated DriverProvider yet.
// In a full implementation, this uses ref.watch(driverListProvider);
const _mockDrivers = [
  {'id': 'D-101', 'name': 'Ana Silva'},
  {'id': 'D-102', 'name': 'Carlos Santos'},
  {'id': 'D-103', 'name': 'Beatriz Costa'},
  {'id': 'D-104', 'name': 'João Pereira'}, // Unassigned
];

/// Provides a consolidated view of Driver <-> Vehicle <-> Route allocations.
/// This is a pure projection deriving state from active trips.
final resourceAllocationProjectionProvider = Provider<ResourceAllocationProjection>((
  ref,
) {
  final trips = ref.watch(enrichedTripsProvider);

  // Extract active allocations from ongoing trips
  final Map<String, dynamic> activeAllocationsByDriver = {};
  for (final trip in trips) {
    if (trip.isActive && trip.vehicleId != null) {
      // Assuming trip.id maps to driver in our simulated data model, or we hardcode a mapping
      // For this projection blueprint, we map the vehicle to the first driver pseudo-randomly
      // to demonstrate the shape of the data contract.
      // Real implementation: trip.driverId

      // Fallback pseudo-mapping just for the blueprint validation
      final mockDriverId = 'D-10${(trips.indexOf(trip) % 3) + 1}';

      activeAllocationsByDriver[mockDriverId] = {
        'vehicleId': trip.vehicleId,
        'vehiclePlate': trip.vehicleId, // Using ID as plate for mock
        'tripId': trip.id,
        'routeName': trip.routeShortName ?? 'Linha ${trip.routeId}',
      };
    }
  }

  final nodes = _mockDrivers.map((driverData) {
    final driverId = driverData['id']!;
    final driverName = driverData['name']!;
    final allocation = activeAllocationsByDriver[driverId];

    return ResourceAllocationNode(
      driverId: driverId,
      driverName: driverName,
      assignedVehicleId: allocation?['vehicleId'],
      assignedVehiclePlate: allocation?['vehiclePlate'],
      assignedTripId: allocation?['tripId'],
      assignedRouteName: allocation?['routeName'],
      // Logic for hasConflict: e.g. driver assigned to trip but vehicle has NO connectivity
      hasConflict: false,
    );
  }).toList();

  return ResourceAllocationProjection(nodes: nodes);
});
