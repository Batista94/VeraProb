import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../normalization/models/trip_status_view.dart';
import '../../../domain/enums/trip_status.dart';
import '../../../state/providers/fleet_providers.dart';
import '../models/attention_state.dart';

/// Context for a single vehicle's attention state on the map.
class AttentionContext {
  final AttentionState attentionState;
  final double opacityMultiplier;
  final bool isPulsing;

  const AttentionContext({
    required this.attentionState,
    required this.opacityMultiplier,
    required this.isPulsing,
  });

  static const normal = AttentionContext(
    attentionState: AttentionState.normal,
    opacityMultiplier: 1.0,
    isPulsing: false,
  );
}

/// Global fleet attention projection.
///
/// Derives [AttentionState] for every vehicle using the pure
/// [deriveAttentionState] function. When any vehicle is CRITICAL,
/// all NORMAL vehicles are dimmed to focus operator attention.
class FleetAttentionProjection {
  final bool isFocusModeActive;
  final Map<String, AttentionContext> vehicleStates;

  const FleetAttentionProjection({
    required this.isFocusModeActive,
    required this.vehicleStates,
  });

  AttentionContext getContextFor(String vehicleId) {
    return vehicleStates[vehicleId] ?? AttentionContext.normal;
  }
}

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

  // Build a lookup: tripId → trip for O(1) access
  final tripsByTripId = {for (final t in trips) t.id: t};

  // First pass: derive AttentionState for each vehicle
  final derivedStates = <String, AttentionState>{};
  bool hasCritical = false;

  for (final state in states) {
    final trip = tripsByTripId[state.tripId];
    final attention = deriveAttentionState(
      status: _mapToView(trip?.status ?? TripStatus.enRoute),
      severityScore: trip?.severityScore ?? 0,
      connectivity: state.connectivityState,
      adherence: state.routeAdherence,
    );

    derivedStates[state.vehicleId] = attention;
    if (attention == AttentionState.critical) hasCritical = true;
  }

  // Second pass: compute visual context based on global state
  final vehicleStates = <String, AttentionContext>{};

  for (final entry in derivedStates.entries) {
    final vehicleId = entry.key;
    final attention = entry.value;

    switch (attention) {
      case AttentionState.critical:
        vehicleStates[vehicleId] = const AttentionContext(
          attentionState: AttentionState.critical,
          opacityMultiplier: 1.0,
          isPulsing: true,
        );
      case AttentionState.warning:
        vehicleStates[vehicleId] = AttentionContext(
          attentionState: AttentionState.warning,
          opacityMultiplier: hasCritical ? 0.85 : 1.0,
          isPulsing: false,
        );
      case AttentionState.normal:
        vehicleStates[vehicleId] = AttentionContext(
          attentionState: AttentionState.normal,
          opacityMultiplier: hasCritical ? 0.6 : 1.0,
          isPulsing: false,
        );
    }
  }

  return FleetAttentionProjection(
    isFocusModeActive: hasCritical,
    vehicleStates: vehicleStates,
  );
});

TripStatusView _mapToView(TripStatus domain) {
  return TripStatusView.values.byName(domain.name);
}
