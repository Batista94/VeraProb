import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/application/projections/providers/command_center_filter_provider.dart';
import 'package:veraprob/dev/performance_metrics.dart';
import 'package:veraprob/state/providers/sla_risk_providers.dart';

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
          color: VeraProbColors.surface,
          border: Border(bottom: BorderSide(color: VeraProbColors.border)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            _KpiChip(
              icon: Icons.directions_bus,
              value: '${summary.totalActive}',
              label: 'Em Operação',
              color: VeraProbColors.primary,
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
              color: VeraProbColors.onTime,
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
              color: VeraProbColors.delayed,
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
                  ? VeraProbColors.critical
                  : VeraProbColors.textDisabled,
              isSelected: statusFilter == FleetStatusFilter.alerts,
              onTap: () => ref
                  .read(commandCenterFilterProvider.notifier)
                  .setStatusFilter(FleetStatusFilter.alerts),
            ),
            _divider(),
            _KpiChip(
              icon: Icons.gps_off,
              value: '${summary.alerts}',
              label: 'Anomalias GPS',
              color: VeraProbColors.delayed,
              isSelected: statusFilter == FleetStatusFilter.kinematicAnomaly,
              onTap: () => ref
                  .read(commandCenterFilterProvider.notifier)
                  .setStatusFilter(FleetStatusFilter.kinematicAnomaly),
            ),
            _divider(),
            _KpiChip(
              icon: Icons.hail,
              value: '${summary.atStop}',
              label: 'No Ponto',
              color: VeraProbColors.scheduled,
              isSelected: statusFilter == FleetStatusFilter.atStop,
              onTap: () => ref
                  .read(commandCenterFilterProvider.notifier)
                  .setStatusFilter(FleetStatusFilter.atStop),
            ),
            _divider(),
            switch (ref.watch(atRiskSlaCountProvider)) {
              AsyncData(:final value) => _KpiChip(
                icon: Icons.alarm_rounded,
                value: '$value',
                label: 'SLA em Risco',
                color: value > 0
                    ? VeraProbColors.warning
                    : VeraProbColors.textDisabled,
                isSelected: false,
                onTap: () {},
              ),
              AsyncLoading() => const SizedBox(width: 80),
              AsyncError() => const SizedBox.shrink(),
            },
            const Spacer(),
            // Average delay
            if (summary.avgDelayMinutes > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: VeraProbColors.delayed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'Atraso médio: ${summary.avgDelayMinutes} min',
                  style: VeraProbTypography.caption.copyWith(
                    color: VeraProbColors.delayed,
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
      color: VeraProbColors.border,
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
                  style: VeraProbTypography.caption.copyWith(
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
