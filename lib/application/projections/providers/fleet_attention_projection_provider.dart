import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/enums/route_adherence.dart';
import '../../../state/providers/fleet_providers.dart';

class AttentionContext {
  final double opacityMultiplier;
  final bool isPulsing;

  const AttentionContext({
    required this.opacityMultiplier,
    required this.isPulsing,
  });
}

class FleetAttentionProjection {
  final bool isFocusModeActive;
  final Map<String, AttentionContext> vehicleStates;

  const FleetAttentionProjection({
    required this.isFocusModeActive,
    required this.vehicleStates,
  });

  AttentionContext getContextFor(String vehicleId) {
    return vehicleStates[vehicleId] ??
        const AttentionContext(opacityMultiplier: 1.0, isPulsing: false);
  }
}

/// Computes global attention logic.
/// Fades out normal vehicles if there is any critical incident or off-route vehicle.
final fleetAttentionProjectionProvider = Provider<FleetAttentionProjection>((
  ref,
) {
  final trips = ref.watch(enrichedTripsProvider);
  final positionsAsync = ref.watch(normalizedStateProvider);

  if (!positionsAsync.hasValue) {
    return const FleetAttentionProjection(
      isFocusModeActive: false,
      vehicleStates: {},
    );
  }

  final states = positionsAsync.value!;

  final criticalVehicleIds = <String>{};

  for (final state in states) {
    if (state.routeAdherence == RouteAdherence.offRoute) {
      criticalVehicleIds.add(state.vehicleId);
      continue;
    }

    final trip = trips.where((t) => t.id == state.tripId).firstOrNull;
    if (trip != null && trip.severityScore >= 3) {
      criticalVehicleIds.add(state.vehicleId);
    }
  }

  final isFocusModeActive = criticalVehicleIds.isNotEmpty;
  final vehicleStates = <String, AttentionContext>{};

  for (final state in states) {
    if (isFocusModeActive) {
      if (criticalVehicleIds.contains(state.vehicleId)) {
        // Critical: Full opacity, pulsating shadow
        vehicleStates[state.vehicleId] = const AttentionContext(
          opacityMultiplier: 1.0,
          isPulsing: true,
        );
      } else {
        // Normal during Incident: Dimmed
        vehicleStates[state.vehicleId] = const AttentionContext(
          opacityMultiplier: 0.6, // Visibility increased from 0.2 to 0.6
          isPulsing: false,
        );
      }
    } else {
      // Normal map
      vehicleStates[state.vehicleId] = const AttentionContext(
        opacityMultiplier: 1.0,
        isPulsing: false,
      );
    }
  }

  return FleetAttentionProjection(
    isFocusModeActive: isFocusModeActive,
    vehicleStates: vehicleStates,
  );
});
