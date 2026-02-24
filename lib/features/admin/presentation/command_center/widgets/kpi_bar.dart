import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/state/providers/fleet_providers.dart';

/// The KPI bar at the top of the Command Center.
/// Shows key fleet metrics in real-time.
class KpiBar extends ConsumerWidget {
  const KpiBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(fleetSummaryProvider);

    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: BusFlowColors.surface,
        border: Border(bottom: BorderSide(color: BusFlowColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _KpiChip(
            icon: Icons.directions_bus,
            value: '${summary.totalActive}',
            label: 'Em Operação',
            color: BusFlowColors.primary,
          ),
          _divider(),
          _KpiChip(
            icon: Icons.check_circle_outline,
            value: '${summary.onTime}',
            label: 'No Horário',
            color: BusFlowColors.onTime,
          ),
          _divider(),
          _KpiChip(
            icon: Icons.warning_amber_rounded,
            value: '${summary.delayed}',
            label: 'Atrasados',
            color: BusFlowColors.delayed,
          ),
          _divider(),
          _KpiChip(
            icon: Icons.error_outline,
            value: '${summary.alerts}',
            label: 'Alertas',
            color: summary.alerts > 0
                ? BusFlowColors.critical
                : BusFlowColors.textDisabled,
          ),
          _divider(),
          _KpiChip(
            icon: Icons.hail,
            value: '${summary.atStop}',
            label: 'No Ponto',
            color: BusFlowColors.scheduled,
          ),
          const Spacer(),
          // Average delay
          if (summary.avgDelayMinutes > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: BusFlowColors.delayed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Atraso médio: ${summary.avgDelayMinutes} min',
                style: BusFlowTypography.caption.copyWith(
                  color: BusFlowColors.delayed,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _divider() {
    return Container(
      height: 24,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: BusFlowColors.border,
    );
  }
}

class _KpiChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _KpiChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: color,
                height: 1.1,
              ),
            ),
            Text(
              label,
              style: BusFlowTypography.caption.copyWith(fontSize: 10),
            ),
          ],
        ),
      ],
    );
  }
}
