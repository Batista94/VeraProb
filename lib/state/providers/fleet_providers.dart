import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/operational_control_service.dart';
import '../../application/simulation_control_service.dart';
import '../../data/services/fleet_simulation_service.dart';
import '../../domain/entities/operational_trip.dart';
import '../../domain/entities/trip_event.dart';
import '../../domain/entities/vehicle_position.dart';
import '../../domain/enums/trip_status.dart';

// ── Core Service Provider ──────────────────────────────

final fleetSimulationProvider = Provider<FleetSimulationService>((ref) {
  return FleetSimulationService();
});

// ── Operational Control Service ────────────────────────

final operationalControlProvider = Provider<OperationalControlService>((ref) {
  final simulation = ref.read(fleetSimulationProvider);
  return SimulationControlService(simulation);
});

// ── UI Refresh Counter ─────────────────────────────────
// Incremented after every mutation to force providers to re-evaluate.

final uiRefreshTrigger = StateProvider<int>((ref) => 0);

void triggerUIRefresh(WidgetRef ref) {
  ref.read(uiRefreshTrigger.notifier).state++;
}

// ── Trip Stream ────────────────────────────────────────

/// Stream of all operational trips, updated every 15 seconds.
final tripStreamProvider = StreamProvider<List<OperationalTrip>>((ref) {
  final simulation = ref.read(fleetSimulationProvider);
  return simulation.tripStream(interval: const Duration(seconds: 15));
});

/// All active trips (non-terminal)
final activeTripsProvider = Provider<List<OperationalTrip>>((ref) {
  ref.watch(uiRefreshTrigger);
  final tripsAsync = ref.watch(tripStreamProvider);
  return tripsAsync.maybeWhen(
    data: (trips) => trips.where((t) => t.isActive).toList(),
    orElse: () => [],
  );
});

// ── Position Stream ────────────────────────────────────

/// Stream of vehicle positions, updated every 15 seconds.
final positionStreamProvider = StreamProvider<List<VehiclePosition>>((ref) {
  final simulation = ref.read(fleetSimulationProvider);
  return simulation.positionStream(interval: const Duration(seconds: 15));
});

// ── Selected Trip ──────────────────────────────────────

/// Currently selected trip in the Command Center.
final selectedTripIdProvider = StateProvider<String?>((ref) => null);

/// The selected operational trip object.
final selectedTripProvider = Provider<OperationalTrip?>((ref) {
  final selectedId = ref.watch(selectedTripIdProvider);
  if (selectedId == null) return null;

  ref.watch(uiRefreshTrigger);
  final tripsAsync = ref.watch(tripStreamProvider);
  return tripsAsync.maybeWhen(
    data: (trips) {
      try {
        return trips.firstWhere((t) => t.id == selectedId);
      } catch (_) {
        return null;
      }
    },
    orElse: () => null,
  );
});

// ── Trip Events ────────────────────────────────────────

/// Events for the currently selected trip.
final selectedTripEventsProvider = Provider<List<TripEvent>>((ref) {
  final selectedId = ref.watch(selectedTripIdProvider);
  if (selectedId == null) return [];

  ref.watch(uiRefreshTrigger);
  final simulation = ref.read(fleetSimulationProvider);
  return simulation.getEventsForTrip(selectedId);
});

// ── Fleet Summary (KPIs) ──────────────────────────────

class FleetSummary {
  final int totalActive;
  final int onTime;
  final int delayed;
  final int alerts;
  final int atStop;
  final int avgDelayMinutes;

  const FleetSummary({
    this.totalActive = 0,
    this.onTime = 0,
    this.delayed = 0,
    this.alerts = 0,
    this.atStop = 0,
    this.avgDelayMinutes = 0,
  });
}

final fleetSummaryProvider = Provider<FleetSummary>((ref) {
  ref.watch(uiRefreshTrigger);
  final tripsAsync = ref.watch(tripStreamProvider);

  return tripsAsync.maybeWhen(
    data: (trips) {
      final active = trips.where((t) => t.isActive).toList();
      final onTime = active
          .where(
            (t) =>
                t.status == TripStatus.enRoute || t.status == TripStatus.atStop,
          )
          .length;
      final delayed = active
          .where((t) => t.status == TripStatus.delayed)
          .length;
      final alerts = active.where((t) => t.status.requiresAttention).length;
      final atStop = active.where((t) => t.status == TripStatus.atStop).length;

      final totalDelay = active.fold<int>(0, (sum, t) => sum + t.delaySeconds);
      final avgDelay = active.isEmpty
          ? 0
          : (totalDelay / active.length / 60).round();

      return FleetSummary(
        totalActive: active.length,
        onTime: onTime,
        delayed: delayed,
        alerts: alerts,
        atStop: atStop,
        avgDelayMinutes: avgDelay,
      );
    },
    orElse: () => const FleetSummary(),
  );
});

// ── Filter Providers ───────────────────────────────────

final tripStatusFilterProvider = StateProvider<TripStatus?>((ref) => null);

final filteredTripsProvider = Provider<List<OperationalTrip>>((ref) {
  ref.watch(uiRefreshTrigger);
  final tripsAsync = ref.watch(tripStreamProvider);
  final statusFilter = ref.watch(tripStatusFilterProvider);

  return tripsAsync.maybeWhen(
    data: (trips) {
      var filtered = trips.where((t) => t.isActive).toList();
      if (statusFilter != null) {
        filtered = filtered.where((t) => t.status == statusFilter).toList();
      }
      filtered.sort((a, b) {
        if (a.requiresAttention && !b.requiresAttention) return -1;
        if (!a.requiresAttention && b.requiresAttention) return 1;
        return b.delaySeconds.compareTo(a.delaySeconds);
      });
      return filtered;
    },
    orElse: () => [],
  );
});
