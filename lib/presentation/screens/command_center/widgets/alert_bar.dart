import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/fleet_providers.dart';

/// Bottom alert bar showing attention-requiring events.
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
            '${alertTrips.length} ALERTAS:',
            style: BusFlowTypography.badge.copyWith(
              color: BusFlowColors.critical,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: alertTrips.length,
              separatorBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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
                  child: GestureDetector(
                    onTap: () {
                      ref.read(selectedTripIdProvider.notifier).state = trip.id;
                    },
                    child: Text(
                      '${trip.routeShortName ?? trip.routeId} — '
                      '${trip.status.label} '
                      '${trip.delaySeconds > 0 ? trip.delayDisplay : ""}',
                      style: BusFlowTypography.caption.copyWith(
                        color: BusFlowColors.textPrimary,
                      ),
                    ),
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
