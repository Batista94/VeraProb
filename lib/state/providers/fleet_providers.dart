import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../application/intelligence/situation_engine.dart';
import '../../application/operational_control_service.dart';
import '../../application/simulation_control_service.dart';
import '../../data/services/fleet_simulation_service.dart';
import '../../domain/entities/operational_trip.dart';
import '../../domain/entities/trip_event.dart';
import '../../domain/entities/vehicle_position.dart';
import '../../domain/enums/trip_status.dart';

// ── Core Services ──────────────────────────────────────

final fleetSimulationProvider = Provider<FleetSimulationService>((ref) {
  return FleetSimulationService();
});

final operationalControlProvider = Provider<OperationalControlService>((ref) {
  final simulation = ref.read(fleetSimulationProvider);
  return SimulationControlService(simulation);
});

// Sprint 3: The Intelligence Engine
final situationEngineProvider = Provider<SituationEngine>((ref) {
  return SituationEngine();
});

// ── UI Refresh Counter ─────────────────────────────────
// Incremented after every mutation to force providers to re-evaluate.

final uiRefreshTrigger = StateProvider<int>((ref) => 0);

void triggerUIRefresh(WidgetRef ref) {
  ref.read(uiRefreshTrigger.notifier).state++;
}

// ── Trip Stream ────────────────────────────────────────

/// Stream of all raw operational trips, updated every 15 seconds.
final tripStreamProvider = StreamProvider<List<OperationalTrip>>((ref) {
  final simulation = ref.read(fleetSimulationProvider);
  return simulation.tripStream(interval: const Duration(seconds: 15));
});

/// Intelligent stream of trips enriched by the SituationEngine
final enrichedTripsProvider = Provider<List<OperationalTrip>>((ref) {
  ref.watch(uiRefreshTrigger);
  final tripsAsync = ref.watch(tripStreamProvider);
  final engine = ref.watch(situationEngineProvider);
  final control = ref.read(operationalControlProvider);

  return tripsAsync.maybeWhen(
    data: (rawTrips) {
      // Pass raw trips through the intelligence engine
      return engine.analyze(rawTrips, control);
    },
    orElse: () => [],
  );
});

/// All active, enriched trips (non-terminal)
final activeTripsProvider = Provider<List<OperationalTrip>>((ref) {
  final enrichedTrips = ref.watch(enrichedTripsProvider);
  return enrichedTrips.where((t) => t.isActive).toList();
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

/// The selected, enriched operational trip object.
final selectedTripProvider = Provider<OperationalTrip?>((ref) {
  final selectedId = ref.watch(selectedTripIdProvider);
  if (selectedId == null) return null;

  final enrichedTrips = ref.watch(enrichedTripsProvider);
  try {
    return enrichedTrips.firstWhere((t) => t.id == selectedId);
  } catch (_) {
    return null;
  }
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
  final enrichedTrips = ref.watch(enrichedTripsProvider);
  final active = enrichedTrips.where((t) => t.isActive).toList();

  if (active.isEmpty) return const FleetSummary();

  final onTime = active
      .where(
        (t) => t.status == TripStatus.enRoute || t.status == TripStatus.atStop,
      )
      .length;
  final delayed = active.where((t) => t.status == TripStatus.delayed).length;
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
});

// ── Filter Providers ───────────────────────────────────

final tripStatusFilterProvider = StateProvider<TripStatus?>((ref) => null);

/// Filtered trips sorted intelligently (Severity Score > Attention > Delay)
final filteredTripsProvider = Provider<List<OperationalTrip>>((ref) {
  final enrichedTrips = ref.watch(enrichedTripsProvider);
  var active = enrichedTrips.where((t) => t.isActive).toList();

  final statusFilter = ref.watch(tripStatusFilterProvider);
  if (statusFilter != null) {
    active = active.where((t) => t.status == statusFilter).toList();
  }

  active.sort((a, b) {
    // 1. Highest severity score first (Sprint 3)
    if (a.severityScore != b.severityScore) {
      return b.severityScore.compareTo(a.severityScore);
    }
    // 2. Requires attention fallback
    if (a.requiresAttention && !b.requiresAttention) return -1;
    if (!a.requiresAttention && b.requiresAttention) return 1;
    // 3. Largest delay fallback
    return b.delaySeconds.compareTo(a.delaySeconds);
  });

  return active;
});
