import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_query_service.dart';
import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/sla_audit/supabase_fleet_health_query_service.dart';
import 'package:veraprob/state/provider_timeout.dart';
import 'auth_providers.dart';

// ── Infrastructure Binding ───────────────────────────────────────────────────

/// Provides the [FleetHealthQueryService] backed by Supabase.
///
/// Mirrors the [heartbeatQueryServiceProvider] pattern.
final fleetHealthQueryServiceProvider = Provider<FleetHealthQueryService>((
  ref,
) {
  return SupabaseFleetHealthQueryService(ref.watch(supabaseClientProvider));
});

// ── One-Shot Fetch ───────────────────────────────────────────────────────────

/// Returns the fleet health snapshot for [organizationId] (INV-1).
///
/// One-shot fetch — use [fleetHealthPollingProvider] for continuous monitoring.
final fleetHealthProvider = FutureProvider.family<FleetHealthView, String>((
  ref,
  organizationId,
) async {
  final service = ref.watch(fleetHealthQueryServiceProvider);
  return service
      .getFleetHealth(organizationId: organizationId)
      .withProviderTimeout();
});

// ── Polling Stream (60s) ─────────────────────────────────────────────────────

/// Continuously polls fleet health every 60 seconds.
///
/// `autoDispose` ensures the timer is cancelled on screen exit, preventing
/// memory leaks and unnecessary connection usage (INV-16).
///
/// Supabase Realtime is intentionally NOT used on `canonical_facts` because
/// the write volume on ingestion tables would flood WebSocket channels and
/// risk connection exhaustion (Disponibilidade).
final fleetHealthPollingProvider = StreamProvider.autoDispose<FleetHealthView>((
  ref,
) {
  final orgId = ref.watch(currentOrganizationIdProvider);
  if (orgId == null) {
    return Stream.value(
      const FleetHealthView(
        vehicles: [],
        healthyCount: 0,
        delayedCount: 0,
        offlineCount: 0,
        neverSeenCount: 0,
        fleetActiveRatioBps: 0,
      ),
    );
  }

  final service = ref.watch(fleetHealthQueryServiceProvider);

  // StreamController for clean timer lifecycle management.
  final controller = StreamController<FleetHealthView>();
  Timer? timer;

  Future<void> fetch() async {
    try {
      final view = await service.getFleetHealth(organizationId: orgId);
      if (!controller.isClosed) {
        controller.add(view);
      }
    } on Object catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  // Initial fetch immediately, then every 60s.
  fetch();
  timer = Timer.periodic(const Duration(seconds: 60), (_) => fetch());

  ref.onDispose(() {
    timer?.cancel();
    controller.close();
  });

  return controller.stream;
});

// ── Drill-Down Selection ─────────────────────────────────────────────────────

class SelectedHealthVehicleIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

/// Selected vehicle ID for the detail panel drill-down.
///
/// Set by the alert tap handler or by clicking a vehicle in the grid.
/// `null` means no vehicle is selected (detail panel collapsed).
final selectedHealthVehicleIdProvider =
    NotifierProvider<SelectedHealthVehicleIdNotifier, String?>(
      SelectedHealthVehicleIdNotifier.new,
    );

// ── Preselection Validation ──────────────────────────────────────────────────

/// Validates [candidateId] against the org's loaded fleet (INV-22 / INV-26).
///
/// Returns [candidateId] when found in the fleet; `null` when data is still
/// pending (stream not yet emitted) OR when the id is absent from the org's
/// fleet. Callers distinguish the two cases by reading
/// [fleetHealthPollingProvider] separately — Anti-Oracle compliance requires
/// that "pending" and "absent" produce identical UI (no id in error messages).
final resolvedPreselectionProvider = Provider.family<String?, String?>((
  ref,
  candidateId,
) {
  if (candidateId == null || candidateId.isEmpty) return null;
  final view = ref.watch(fleetHealthPollingProvider).asData?.value;
  if (view == null) return null;
  final ids = <String>{
    for (final e in view.vehicles)
      if ((e.vehicleId ?? e.deviceId) != null) e.vehicleId ?? e.deviceId!,
  };
  return ids.contains(candidateId) ? candidateId : null;
});
