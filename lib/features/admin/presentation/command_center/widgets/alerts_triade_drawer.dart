import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/sla_audit/alert_impact_calculator.dart'
    show AlertSeverityTier;
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
      width: (MediaQuery.sizeOf(context).width * 0.26).clamp(280.0, 360.0),
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
                    Flexible(
                      child: Text(
                        trip.routeDisplay,
                        style: VeraProbTypography.sectionTitle.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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
            const SizedBox(height: 8),
            _FinancialImpactBadge(delaySeconds: trip.delaySeconds),
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

/// Displays an estimated financial impact badge based on delay seconds.
///
/// Uses a heuristic estimate (R$5/min) since the alert card does not
/// carry full SLAPenalties context. The tier color communicates urgency.
class _FinancialImpactBadge extends StatelessWidget {
  final int delaySeconds;

  const _FinancialImpactBadge({required this.delaySeconds});

  @override
  Widget build(BuildContext context) {
    final delayMinutes = delaySeconds ~/ 60;
    if (delayMinutes <= 0) return const SizedBox.shrink();

    // Heuristic: R$5.00/min estimate for display purposes
    final estimatedCents = delayMinutes * 500;
    final tier = AlertSeverityTier.fromCents(estimatedCents);
    final reais = (estimatedCents / 100).toStringAsFixed(2);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _tierColor(tier).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _tierColor(tier).withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.attach_money, size: 14, color: _tierColor(tier)),
          const SizedBox(width: 4),
          Text(
            'Impacto estimado: R\$ $reais',
            style: VeraProbTypography.caption.copyWith(
              color: _tierColor(tier),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static Color _tierColor(AlertSeverityTier tier) {
    switch (tier) {
      case AlertSeverityTier.low:
        return VeraProbColors.textSecondary;
      case AlertSeverityTier.medium:
        return VeraProbColors.delayed;
      case AlertSeverityTier.high:
        return VeraProbColors.critical;
      case AlertSeverityTier.critical:
        return const Color(0xFFFF1744);
    }
  }
}
