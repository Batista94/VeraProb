import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_providers.dart';
import '../../application/intelligence/situation_engine.dart';
import '../../application/operational_control_service.dart';
import '../../application/simulation_control_service.dart';
import '../../data/services/fleet_simulation_service.dart';
import '../../domain/entities/operational_trip.dart';
import '../../domain/sla_audit/sla_ledger_entry.dart';
import '../../domain/entities/vehicle_position.dart';
import '../../domain/entities/vehicle_operational_state.dart';
import '../../application/audit/audit_service.dart';
import '../../application/normalization/operational_state_normalizer.dart';
import '../../application/adapters/operational_data_provider.dart';
import '../../application/adapters/realtime_data_provider.dart';
import '../../application/adapters/stress_scenario_config.dart';
import '../../domain/enums/trip_status.dart';
import '../../application/projections/providers/command_center_filter_provider.dart';
import '../../application/projections/providers/fleet_attention_projection_provider.dart';
import '../../application/projections/models/attention_state.dart';
import 'sla_providers.dart';

// ── Core Services ──────────────────────────────────────

/// Optional stress scenario configuration. When set, forces the simulation into stress mode.
/// Can be enabled via passing --dart-define=STRESS_MODE=true
final stressScenarioProvider = StateProvider<StressScenarioConfig?>((ref) {
  const isStressEnabled = bool.fromEnvironment(
    'STRESS_MODE',
    defaultValue: true,
  );
  if (isStressEnabled) {
    return StressScenarioConfig.extreme250();
  }
  return null;
});

final fleetSimulationProvider = Provider<FleetSimulationService>((ref) {
  final config = ref.watch(stressScenarioProvider);
  return FleetSimulationService(config: config);
});

final operationalControlProvider = Provider<OperationalControlService>((ref) {
  final simulation = ref.read(fleetSimulationProvider);
  final audit = ref.read(auditServiceProvider);
  final ledgerRepo = ref.read(slaAuditLedgerRepositoryProvider);
  return SimulationControlService(
    simulation,
    audit,
    ledgerRepo,
    getOperatorId: () =>
        ref.read(currentOperatorIdProvider) ?? 'unauthenticated',
  );
});

// Sprint 3: The Intelligence Engine
final situationEngineProvider = Provider<SituationEngine>((ref) {
  return SituationEngine();
});

// ── UI Refresh Counter ─────────────────────────────────
// Workaround: Incremented after mutations to force `selectedTripEventsProvider`
// to re-read events from FleetSimulationService (which uses synchronous reads,
// not streams). Trip status updates propagate naturally via stream emission
// from _emitCurrentState() and do NOT need this workaround.
// Pending: Replace with a StreamProvider for events in a future data architecture sprint.

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

  // Get the latest stabilized states from the Normalizer
  final normalizedStatesAsync = ref.watch(normalizedStateProvider);
  final statesMap = <String, VehicleOperationalState>{};

  if (normalizedStatesAsync.hasValue) {
    for (final state in normalizedStatesAsync.value!) {
      statesMap[state.vehicleId] = state;
    }
  }

  return tripsAsync.maybeWhen(
    data: (rawTrips) {
      // Pass raw trips and stabilized vehicle states through the intelligence engine
      return engine.analyze(rawTrips, statesMap, control);
    },
    orElse: () => [],
  );
});

/// All active, enriched trips (non-terminal)
final activeTripsProvider = Provider<List<OperationalTrip>>((ref) {
  final enrichedTrips = ref.watch(enrichedTripsProvider);
  return enrichedTrips.where((t) => t.isActive).toList();
});

// ── Data Adapter ─────────────────────────────────────────

/// The operational data adapter.
/// FASE 10: Simulation removed. Only real telemetry via Supabase Realtime.
final operationalDataProvider = Provider<IOperationalDataProvider>((ref) {
  return RealtimeDataProvider();
});

// ── Position Stream ────────────────────────────────────

/// Stream of raw vehicle positions, updated by the active data adapter.
final positionStreamProvider = StreamProvider<List<VehiclePosition>>((ref) {
  final adapter = ref.watch(operationalDataProvider);

  // Ensure the adapter is connected and cleans up when no longer watched
  adapter.connect();
  ref.onDispose(() => adapter.disconnect());

  return adapter.positionStream;
});

/// Singleton instance of the operational state normalizer.
final operationalStateNormalizerProvider = Provider<OperationalStateNormalizer>(
  (ref) {
    return OperationalStateNormalizer();
  },
);

/// Stream of stabilized vehicle operational states.
/// This prevents GPS jitter from reaching the UI or the Situation Engine.
final normalizedStateProvider = StreamProvider<List<VehicleOperationalState>>((
  ref,
) {
  final rawPositionsAsync = ref.watch(positionStreamProvider);
  final normalizer = ref.watch(operationalStateNormalizerProvider);

  return rawPositionsAsync.when(
    data: (rawPositions) {
      // In Phase 1, we don't have Stop geofencing wired up to real stops yet.
      // We pass an empty list, allowing debounce and smoothing to work first.
      return Stream.value(normalizer.normalize(rawPositions, knownStops: []));
    },
    loading: () => Stream.value([]),
    error: (error, stack) => Stream.value([]),
  );
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

/// Forensic evidence timeline for the currently selected trip.
final forensicLedgerProjectionProvider = FutureProvider<List<SlaLedgerEntry>>((
  ref,
) async {
  final selectedId = ref.watch(selectedTripIdProvider);
  if (selectedId == null) return [];

  // Re-fetch when UI triggers an update
  ref.watch(uiRefreshTrigger);

  final ledgerRepo = ref.read(slaAuditLedgerRepositoryProvider);
  final entries = await ledgerRepo.getEntriesBySetId(selectedId);

  // Sort descending (newest first) for UI timeline
  return entries.reversed.toList();
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
  final delayedTrips = active
      .where((t) => t.status == TripStatus.delayed)
      .toList();
  final delayed = delayedTrips.length;

  // Alerts count: CRITICAL attention only (not delayed).
  // We use the attention projection to count vehicles with true emergencies.
  final attentionProjection = ref.watch(fleetAttentionProjectionProvider);
  final alerts = active.where((t) {
    if (t.vehicleId == null) return false;
    final ctx = attentionProjection.getContextFor(t.vehicleId!);
    return ctx.attentionState == AttentionState.critical;
  }).length;
  final atStop = active.where((t) => t.status == TripStatus.atStop).length;

  final totalDelay = delayedTrips.fold<int>(
    0,
    (sum, t) => sum + t.delaySeconds,
  );
  final avgDelay = delayedTrips.isEmpty
      ? 0
      : (totalDelay / delayedTrips.length / 60).round();

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

/// Filtered trips sorted intelligently (Severity Score > Attention > Delay)
final filteredTripsProvider = Provider<List<OperationalTrip>>((ref) {
  final enrichedTrips = ref.watch(enrichedTripsProvider);
  var active = enrichedTrips.where((t) => t.isActive).toList();

  final filterState = ref.watch(commandCenterFilterProvider);
  final statusFilter = filterState.selectedFleetStatusFilter;

  if (statusFilter != FleetStatusFilter.all) {
    active = active.where((t) {
      switch (statusFilter) {
        case FleetStatusFilter.active:
          return t.status.isActive;
        case FleetStatusFilter.onTime:
          return t.status == TripStatus.enRoute ||
              t.status == TripStatus.atStop;
        case FleetStatusFilter.delayed:
          return t.status == TripStatus.delayed;
        case FleetStatusFilter.alerts:
          // OCC Hardening: CRITICAL attention only — delayed is WARNING, not alert
          if (t.vehicleId == null) return false;
          final attProj = ref.watch(fleetAttentionProjectionProvider);
          return attProj.getContextFor(t.vehicleId!).attentionState ==
              AttentionState.critical;

        case FleetStatusFilter.atStop:
          return t.status == TripStatus.atStop;
        case FleetStatusFilter.all:
          return true;
      }
    }).toList();
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
