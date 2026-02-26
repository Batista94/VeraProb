import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/state/providers/fleet_providers.dart';
import 'package:busflow/application/projections/providers/command_center_filter_provider.dart';
import 'package:busflow/dev/performance_metrics.dart';

/// The KPI bar at the top of the Command Center.
/// Shows key fleet metrics in real-time.
class KpiBar extends ConsumerWidget {
  const KpiBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(fleetSummaryProvider);
    final filterState = ref.watch(commandCenterFilterProvider);
    final statusFilter = filterState.selectedFleetStatusFilter;

    return RebuildCounter(
      name: 'KpiBar',
      child: Container(
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
              isSelected: statusFilter == FleetStatusFilter.active,
              onTap: () => ref
                  .read(commandCenterFilterProvider.notifier)
                  .setStatusFilter(FleetStatusFilter.active),
            ),
            _divider(),
            _KpiChip(
              icon: Icons.check_circle_outline,
              value: '${summary.onTime}',
              label: 'No Horário',
              color: BusFlowColors.onTime,
              isSelected: statusFilter == FleetStatusFilter.onTime,
              onTap: () => ref
                  .read(commandCenterFilterProvider.notifier)
                  .setStatusFilter(FleetStatusFilter.onTime),
            ),
            _divider(),
            _KpiChip(
              icon: Icons.warning_amber_rounded,
              value: '${summary.delayed}',
              label: 'Atrasados',
              color: BusFlowColors.delayed,
              isSelected: statusFilter == FleetStatusFilter.delayed,
              onTap: () => ref
                  .read(commandCenterFilterProvider.notifier)
                  .setStatusFilter(FleetStatusFilter.delayed),
            ),
            _divider(),
            _KpiChip(
              icon: Icons.error_outline,
              value: '${summary.alerts}',
              label: 'Alertas',
              color: summary.alerts > 0
                  ? BusFlowColors.critical
                  : BusFlowColors.textDisabled,
              isSelected: statusFilter == FleetStatusFilter.alerts,
              onTap: () => ref
                  .read(commandCenterFilterProvider.notifier)
                  .setStatusFilter(FleetStatusFilter.alerts),
            ),
            _divider(),
            _KpiChip(
              icon: Icons.hail,
              value: '${summary.atStop}',
              label: 'No Ponto',
              color: BusFlowColors.scheduled,
              isSelected: statusFilter == FleetStatusFilter.atStop,
              onTap: () => ref
                  .read(commandCenterFilterProvider.notifier)
                  .setStatusFilter(FleetStatusFilter.atStop),
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
  final bool isSelected;
  final VoidCallback onTap;

  const _KpiChip({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.25)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? color.withValues(alpha: 0.8)
                : Colors.transparent,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            if (isSelected) ...[
              const SizedBox(width: 3),
              Text('●', style: TextStyle(fontSize: 6, color: color)),
            ],
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
                  style: BusFlowTypography.caption.copyWith(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
