import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../state/providers/fleet_providers.dart';
import '../../../domain/enums/connectivity_state.dart';
import '../models/command_center_kpis.dart';

/// Provides high-level aggregated KPIs for the command center.
/// Uses a pure function, recalculating only when necessary.
/// Future: use Riverpod's select or a timer for debouncing if updates are too frequent.
final kpiProjectionProvider = Provider<CommandCenterKPIs>((ref) {
  final normalizedStatesAsync = ref.watch(normalizedStateProvider);
  final trips = ref.watch(enrichedTripsProvider);

  if (!normalizedStatesAsync.hasValue) {
    return const CommandCenterKPIs();
  }

  final states = normalizedStatesAsync.value!;

  final activeVehiclesCount = states.length;

  // Signal Loss Rate calculation
  final signalLostCount = states
      .where((s) => s.connectivityState == ConnectivityState.signalLost)
      .length;

  final signalLossRate = activeVehiclesCount > 0
      ? signalLostCount / activeVehiclesCount
      : 0.0;

  // Global Punctuality calculation
  // Percentage of trips without 'DELAY' warnings
  final totalActiveTrips = trips.where((t) => t.isActive).length;
  final delayedTripsCount = trips
      .where((t) => t.isActive && t.warnings.any((w) => w.type == 'DELAY'))
      .length;

  final globalPunctuality = totalActiveTrips > 0
      ? 1.0 - (delayedTripsCount / totalActiveTrips)
      : 1.0;

  // Open Incidents
  final openIncidentsCount = trips
      .expand((t) => t.warnings)
      .where(
        (w) => w.severityScore >= 3,
      ) // Example threshold for "Incident", e.g. severity 3+
      .length;

  return CommandCenterKPIs(
    activeVehicles: activeVehiclesCount,
    signalLossRate: signalLossRate,
    globalPunctuality: globalPunctuality,
    openIncidents:
        openIncidentsCount, // Assuming warnings without end time are open
  );
});
