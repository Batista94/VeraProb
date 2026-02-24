import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/state/providers/fleet_providers.dart';

/// Bottom alert bar showing attention-requiring events.
///
/// Sprint 2: Now supports click-to-select and inline resolve action.
class AlertBar extends ConsumerWidget {
  const AlertBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(filteredTripsProvider);
    final alertTrips = trips.where((t) => t.requiresAttention).toList();

    if (alertTrips.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: BusFlowColors.critical.withValues(alpha: 0.1),
        border: const Border(
          top: BorderSide(color: BusFlowColors.critical, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 16,
            color: BusFlowColors.critical,
          ),
          const SizedBox(width: 8),
          Text(
            '${alertTrips.length} ALERTA${alertTrips.length > 1 ? 'S' : ''}:',
            style: BusFlowTypography.badge.copyWith(
              color: BusFlowColors.critical,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: alertTrips.length,
              separatorBuilder: (_, _) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '│',
                  style: TextStyle(
                    color: BusFlowColors.critical.withValues(alpha: 0.4),
                  ),
                ),
              ),
              itemBuilder: (context, index) {
                final trip = alertTrips[index];
                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Click to select this trip (opens drawer)
                      GestureDetector(
                        onTap: () {
                          ref.read(selectedTripIdProvider.notifier).state =
                              trip.id;
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Text(
                            '${trip.routeShortName ?? trip.routeId} — '
                            '${trip.status.label} '
                            '${trip.delaySeconds > 0 ? trip.delayDisplay : ""}',
                            style: BusFlowTypography.caption.copyWith(
                              color: BusFlowColors.textPrimary,
                              decoration: TextDecoration.underline,
                              decorationColor: BusFlowColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Inline resolve button
                      GestureDetector(
                        onTap: () async {
                          final control = ref.read(operationalControlProvider);
                          await control.resolveAlert(trip.id);
                          triggerUIRefresh(ref);
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              border: Border.all(
                                color: BusFlowColors.onTime.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check,
                                  size: 10,
                                  color: BusFlowColors.onTime,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Tratado',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: BusFlowColors.onTime,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
