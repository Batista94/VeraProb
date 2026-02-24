import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/vehicle_operational_state.dart';
import '../../../domain/enums/connectivity_state.dart';
import '../../../domain/enums/trip_status.dart';
import '../../../domain/enums/route_adherence.dart';
import '../../../state/providers/fleet_providers.dart';
import 'command_center_filter_provider.dart';
import '../models/fleet_status_projection.dart';

/// Provides a synchronous, grouped pure projection of the fleet's operational status.
final fleetStatusProjectionProvider = Provider<FleetStatusProjection>((ref) {
  // Listen to the normalized states (pure pure data, no I/O)
  final normalizedStatesAsync = ref.watch(normalizedStateProvider);

  if (normalizedStatesAsync.isLoading || !normalizedStatesAsync.hasValue) {
    return const FleetStatusProjection();
  }

  final states = normalizedStatesAsync.value!;
  final trips = ref.watch(enrichedTripsProvider);

  // Set of trip IDs that have a delay warning from SituationEngine
  final delayedTripIds = trips
      .where((t) => t.warnings.any((w) => w.type == 'DELAY'))
      .map((t) => t.id)
      .toSet();

  final filterState = ref.watch(commandCenterFilterProvider);

  final active = <VehicleOperationalState>[];
  final delayed = <VehicleOperationalState>[];
  final offRoute = <VehicleOperationalState>[];
  final signalLost = <VehicleOperationalState>[];
  final allFiltered = <VehicleOperationalState>[];

  for (final state in states) {
    bool hasIssue = false;

    // Evaluate if it passes global status filters
    final trip = trips.where((t) => t.id == state.tripId).firstOrNull;
    final status = trip?.status ?? TripStatus.scheduled;

    bool passesFilter = true;
    switch (filterState.selectedFleetStatusFilter) {
      case FleetStatusFilter.all:
        break;
      case FleetStatusFilter.active:
        if (!status.isActive) {
          passesFilter = false;
        }
        break;
      case FleetStatusFilter.onTime:
        if (status != TripStatus.enRoute && status != TripStatus.atStop) {
          passesFilter = false;
        }
        break;
      case FleetStatusFilter.delayed:
        if (status != TripStatus.delayed) {
          passesFilter = false;
        }
        break;
      case FleetStatusFilter.alerts:
        if (!status.requiresAttention) {
          passesFilter = false;
        }
        break;
      case FleetStatusFilter.atStop:
        if (status != TripStatus.atStop) {
          passesFilter = false;
        }
        break;
    }

    if (!passesFilter) {
      continue;
    }
    allFiltered.add(state);

    // Grouping
    // Signal Loss
    if (state.connectivityState == ConnectivityState.signalLost) {
      signalLost.add(state);
      hasIssue = true;
    }

    // Off Route
    if (state.routeAdherence == RouteAdherence.offRoute) {
      offRoute.add(state);
      hasIssue = true;
    }

    // Delayed
    if (delayedTripIds.contains(state.tripId)) {
      delayed.add(state);
      hasIssue = true;
    }

    // Active (working normally)
    if (!hasIssue) {
      active.add(state);
    }
  }

  return FleetStatusProjection(
    activeVehicles: active,
    delayedVehicles: delayed,
    offRouteVehicles: offRoute,
    signalLostVehicles: signalLost,
    allFilteredVehicles: allFiltered,
  );
});
