import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../state/providers/fleet_providers.dart';
import 'widgets/fleet_map.dart';
import 'widgets/kpi_bar.dart';
import 'widgets/trip_sidebar.dart';
import 'widgets/alert_bar.dart';
import 'widgets/vehicle_detail_drawer.dart';

/// The Command Center — the primary screen operators see 90% of the time.
///
/// Sprint 2: Now with operational actions, occurrence modal, and evolved alert bar.
///
/// Layout:
/// ┌─ KPI BAR ──────────────────────────────────────────────────┐
/// ├──────────┬───────────────────────────┬──────────────────────┤
/// │ TRIP     │                           │ VEHICLE DETAIL       │
/// │ SIDEBAR  │     FLEET MAP             │ DRAWER               │
/// │ (280px)  │                           │ (340px, conditional) │
/// ├──────────┴───────────────────────────┴──────────────────────┤
/// │ ALERT BAR (36px, conditional) — with resolve actions       │
/// └────────────────────────────────────────────────────────────┘
class CommandCenterScreen extends ConsumerWidget {
  const CommandCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedTrip = ref.watch(selectedTripProvider);

    return Container(
      color: BusFlowColors.background,
      child: Column(
        children: [
          // ── KPI Bar ────────────────────────────────
          const KpiBar(),

          // ── Main Content ───────────────────────────
          Expanded(
            child: Row(
              children: [
                // Trip Sidebar (left)
                const TripSidebar(),

                // Fleet Map (center, fills remaining space)
                const Expanded(child: FleetMap()),

                // Vehicle Detail Drawer (right, conditional)
                if (selectedTrip != null)
                  VehicleDetailDrawer(
                    trip: selectedTrip,
                    onClose: () {
                      ref.read(selectedTripIdProvider.notifier).state = null;
                    },
                  ),
              ],
            ),
          ),

          // ── Alert Bar (bottom) ─────────────────────
          const AlertBar(),
        ],
      ),
    );
  }
}
