import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/operational_trip.dart';
import '../../../state/providers/fleet_providers.dart';
import 'widgets/fleet_map.dart';
import 'widgets/kpi_bar.dart';
import 'widgets/trip_sidebar.dart';
import 'widgets/alert_bar.dart';

/// The Command Center — the primary screen operators see 90% of the time.
///
/// Layout:
/// ┌─ KPI BAR ──────────────────────────────────────┐
/// ├──────────┬─────────────────────┬────────────────┤
/// │ TRIP     │                     │  TRIP DETAIL   │
/// │ SIDEBAR  │     FLEET MAP       │  (slide-over)  │
/// │ (280px)  │                     │  (360px)       │
/// ├──────────┴─────────────────────┴────────────────┤
/// │ ALERT BAR (36px, conditional)                    │
/// └──────────────────────────────────────────────────┘
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

                // Trip Detail Panel (right, conditional)
                if (selectedTrip != null)
                  _TripDetailPanel(
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

/// Slide-over panel showing details of the selected trip.
class _TripDetailPanel extends StatelessWidget {
  final OperationalTrip trip;
  final VoidCallback onClose;

  const _TripDetailPanel({required this.trip, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      decoration: const BoxDecoration(
        color: BusFlowColors.surface,
        border: Border(left: BorderSide(color: BusFlowColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: BusFlowColors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 20,
                  decoration: BoxDecoration(
                    color: trip.status.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trip.routeDisplay,
                    style: BusFlowTypography.sectionTitle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  color: BusFlowColors.textSecondary,
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status
                  _DetailRow(
                    icon: trip.status.icon,
                    iconColor: trip.status.color,
                    label: 'Status',
                    value: trip.status.label,
                  ),

                  if (trip.delaySeconds > 0)
                    _DetailRow(
                      icon: Icons.timer_off,
                      iconColor: BusFlowColors.delayed,
                      label: 'Atraso',
                      value: trip.delayDisplay,
                    ),

                  _DetailRow(
                    icon: Icons.trending_up,
                    iconColor: BusFlowColors.primary,
                    label: 'Progresso',
                    value: '${trip.completionPct.toStringAsFixed(0)}%',
                  ),

                  const Divider(color: BusFlowColors.border, height: 24),

                  // Driver
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: 'Motorista',
                    value: trip.driverName ?? 'Não alocado',
                  ),

                  // Vehicle
                  _DetailRow(
                    icon: Icons.directions_bus_outlined,
                    label: 'Veículo',
                    value: trip.vehiclePlate ?? 'Não alocado',
                  ),

                  const Divider(color: BusFlowColors.border, height: 24),

                  // Times
                  _DetailRow(
                    icon: Icons.schedule,
                    label: 'Inicio Programado',
                    value: _formatTime(trip.scheduledStart),
                  ),

                  if (trip.scheduledEnd != null)
                    _DetailRow(
                      icon: Icons.flag_outlined,
                      label: 'Término Programado',
                      value: _formatTime(trip.scheduledEnd!),
                    ),

                  if (trip.actualStart != null)
                    _DetailRow(
                      icon: Icons.play_arrow,
                      label: 'Inicio Real',
                      value: _formatTime(trip.actualStart!),
                    ),

                  const Divider(color: BusFlowColors.border, height: 24),

                  // Source
                  _DetailRow(
                    icon: Icons.source_outlined,
                    label: 'Fonte',
                    value: trip.sourceType,
                  ),

                  _DetailRow(icon: Icons.tag, label: 'ID', value: trip.id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor ?? BusFlowColors.textDisabled),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: BusFlowTypography.caption),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: BusFlowTypography.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
