import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/state/providers/fleet_providers.dart';
import 'alerts_triade_drawer.dart';

/// Bottom alert bar showing attention-requiring events.
///
/// Sprint 2: Now supports click-to-select and inline resolve action.
class AlertBar extends ConsumerWidget {
  const AlertBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trips = ref.watch(filteredTripsProvider);
    final alertTrips = trips.where((t) => t.requiresAttention).toList();

    return InkWell(
      onTap: () {
        ref.read(isAlertsDrawerOpenProvider.notifier).state = true;
      },
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: alertTrips.isNotEmpty
              ? BusFlowColors.critical.withValues(alpha: 0.1)
              : BusFlowColors.background,
          border: Border(
            top: BorderSide(
              color: alertTrips.isNotEmpty
                  ? BusFlowColors.critical
                  : BusFlowColors.border,
              width: 1,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              alertTrips.isNotEmpty
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              size: 16,
              color: alertTrips.isNotEmpty
                  ? BusFlowColors.critical
                  : BusFlowColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              alertTrips.isNotEmpty
                  ? '${alertTrips.length} ALERTA${alertTrips.length > 1 ? 'S' : ''} REQUEREM ATENÇÃO'
                  : 'NENHUM ALERTA ATIVO',
              style: BusFlowTypography.badge.copyWith(
                color: alertTrips.isNotEmpty
                    ? BusFlowColors.critical
                    : BusFlowColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            if (alertTrips.isNotEmpty) ...[
              const Spacer(),
              Text(
                'CLIQUE PARA ABRIR A TRIAGEM',
                style: BusFlowTypography.caption.copyWith(
                  color: BusFlowColors.critical.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.open_in_new,
                size: 14,
                color: BusFlowColors.critical.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
