import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
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
        ref.read(isAlertsDrawerOpenProvider.notifier).set(true);
      },
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: alertTrips.isNotEmpty
              ? VeraProbColors.critical.withValues(alpha: 0.1)
              : VeraProbColors.background,
          border: Border(
            top: BorderSide(
              color: alertTrips.isNotEmpty
                  ? VeraProbColors.critical
                  : VeraProbColors.border,
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
                  ? VeraProbColors.critical
                  : VeraProbColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              alertTrips.isNotEmpty
                  ? '${alertTrips.length} ALERTA${alertTrips.length > 1 ? 'S' : ''} REQUEREM ATENÇÃO'
                  : 'NENHUM ALERTA ATIVO',
              style: VeraProbTypography.badge.copyWith(
                color: alertTrips.isNotEmpty
                    ? VeraProbColors.critical
                    : VeraProbColors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
            if (alertTrips.isNotEmpty) ...[
              const Spacer(),
              Text(
                'CLIQUE PARA ABRIR A TRIAGEM',
                style: VeraProbTypography.caption.copyWith(
                  color: VeraProbColors.critical.withValues(alpha: 0.7),
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.open_in_new,
                size: 14,
                color: VeraProbColors.critical.withValues(alpha: 0.7),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
