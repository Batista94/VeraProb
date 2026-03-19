import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/application/projections/providers/command_center_filter_provider.dart';
import 'package:veraprob/state/providers/authority_providers.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';

/// State to control the visibility of the new Alerts Triade Drawer.
final isAlertsDrawerOpenProvider = StateProvider<bool>((ref) => false);

/// Dedicated right-side drawer for operational incident triaging.
/// Provides a vertical, high-density, action-oriented list of all alerts.
class AlertsTriadeDrawer extends ConsumerWidget {
  const AlertsTriadeDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(filteredTripsProvider);
    final alertTrips = trips.where((t) => t.requiresAttention).toList();

    return Container(
      width: 340,
      decoration: const BoxDecoration(
        color: VeraProbColors.surface,
        border: Border(
          left: BorderSide(color: VeraProbColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ─────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: VeraProbColors.background,
              border: Border(
                bottom: BorderSide(color: VeraProbColors.border, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: VeraProbColors.critical,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Triagem de Alertas',
                      style: VeraProbTypography.sectionTitle.copyWith(
                        color: VeraProbColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(
                    Icons.close,
                    color: VeraProbColors.textSecondary,
                    size: 20,
                  ),
                  onPressed: () {
                    ref.read(isAlertsDrawerOpenProvider.notifier).state = false;
                    ref.read(selectedTripIdProvider.notifier).state = null;
                  },
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 20,
                ),
              ],
            ),
          ),

          // ── Summary ────────────────────────────────────
          if (alertTrips.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Text(
                '${alertTrips.length} ALERTA${alertTrips.length > 1 ? 'S' : ''} ATIVO${alertTrips.length > 1 ? 'S' : ''}',
                style: VeraProbTypography.badge.copyWith(
                  color: VeraProbColors.critical,
                  letterSpacing: 0.5,
                ),
              ),
            ),

          // ── List ───────────────────────────────────────
          Expanded(
            child: alertTrips.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 48,
                          color: VeraProbColors.onTime.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhum alerta pendente',
                          style: VeraProbTypography.bodyMedium.copyWith(
                            color: VeraProbColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: alertTrips.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final trip = alertTrips[index];
                      // Use the selectedTripProvider to highlight the focused row
                      final selectedTripId = ref.watch(selectedTripIdProvider);
                      final isSelected = trip.id == selectedTripId;

                      return _AlertCard(
                        trip: trip,
                        isSelected: isSelected,
                        onTap: () {
                          // Change focused context and setup Follow Vehicle
                          ref.read(selectedTripIdProvider.notifier).state =
                              trip.id;
                          final positions = ref
                              .read(normalizedStateProvider)
                              .valueOrNull;
                          final vehicle = positions
                              ?.where((v) => v.tripId == trip.id)
                              .firstOrNull;
                          if (vehicle != null) {
                            ref
                                .read(commandCenterFilterProvider.notifier)
                                .setFollowVehicleId(vehicle.vehicleId);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  final dynamic trip;
  final bool isSelected;
  final VoidCallback onTap;

  const _AlertCard({
    required this.trip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? VeraProbColors.surfaceElevated
              : VeraProbColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? VeraProbColors.critical.withValues(alpha: 0.5)
                : VeraProbColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: VeraProbColors.critical.withValues(alpha: 0.1),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: trip.status.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: trip.status.color, width: 1),
                      ),
                      child: Text(
                        trip.status.label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: trip.status.color,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      trip.routeDisplay,
                      style: VeraProbTypography.sectionTitle.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Text(
                  trip.delaySeconds > 0 ? trip.delayDisplay : 'Imediato',
                  style: VeraProbTypography.caption.copyWith(
                    color: VeraProbColors.critical,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: VeraProbColors.background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: VeraProbColors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Operador requerido. Acompanhando última posição do veículo para auditoria.',
                      style: VeraProbTypography.caption.copyWith(
                        color: VeraProbColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Resolver (OK)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: VeraProbColors.onTime.withValues(
                      alpha: 0.2,
                    ),
                    foregroundColor: VeraProbColors.onTime,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () async {
                    final facade = ref.read(operationalControlFacadeProvider);
                    try {
                      await facade.resolveAlert(
                        tripId: trip.id,
                        simulateRole: 'level1_operator',
                      );
                      // No triggerUIRefresh needed here — trip status propagates
                      // via FleetSimulationService._emitCurrentState() stream.
                      // (triggerUIRefresh is only needed in VehicleDetailDrawer
                      // where the event timeline reads events synchronously.)
                    } on UnauthorizedActionException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Acesso Negado: ${e.reason}'),
                            backgroundColor: VeraProbColors.critical,
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
