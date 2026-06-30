import 'package:flutter/material.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// KPI summary bar for the Ingestion Health Monitor.
///
/// Displays 4 status count chips (HEALTHY, DELAYED, OFFLINE, NEVER_SEEN)
/// and the fleet-wide active ratio as a progress indicator.
///
/// Industrial Dark palette compliance:
/// - Emerald (#10B981) for HEALTHY
/// - Amber (#FBBF24) for DELAYED
/// - Rose (#F87171) for OFFLINE
/// - Zinc (#64748B) for NEVER_SEEN
class FleetHealthSummaryBar extends StatelessWidget {
  final FleetHealthView healthView;

  const FleetHealthSummaryBar({super.key, required this.healthView});

  @override
  Widget build(BuildContext context) {
    final activePercent = healthView.fleetActiveRatioBps / 100.0;

    return Container(
      padding: const EdgeInsets.all(VeraProbSpacing.md),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StatusChip(
                count: healthView.healthyCount,
                label: HardwareStatusView.healthy.label,
                color: VeraProbColors.onTime,
                icon: Icons.check_circle_outline,
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              _StatusChip(
                count: healthView.delayedCount,
                label: HardwareStatusView.delayed.label,
                color: VeraProbColors.delayed,
                icon: Icons.schedule_outlined,
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              _StatusChip(
                count: healthView.offlineCount,
                label: HardwareStatusView.offline.label,
                color: VeraProbColors.critical,
                icon: Icons.signal_wifi_off_outlined,
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              _StatusChip(
                count: healthView.neverSeenCount,
                label: HardwareStatusView.neverSeen.label,
                color: VeraProbColors.neutral,
                icon: Icons.device_unknown_outlined,
              ),
              if (healthView.phantomCount > 0) ...[
                const SizedBox(width: VeraProbSpacing.sm),
                _StatusChip(
                  count: healthView.phantomCount,
                  label: 'Fantasma',
                  color: VeraProbColors.secondary,
                  icon: Icons.sensors_off_outlined,
                ),
              ],
            ],
          ),
          const SizedBox(height: VeraProbSpacing.md),
          Row(
            children: [
              Text('Frota Ativa', style: VeraProbTypography.kpiLabel),
              const SizedBox(width: VeraProbSpacing.sm),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (healthView.fleetActiveRatioBps / 10000.0).clamp(
                      0.0,
                      1.0,
                    ),
                    backgroundColor: VeraProbColors.surfaceElevated,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      activePercent >= 80
                          ? VeraProbColors.onTime
                          : activePercent >= 50
                          ? VeraProbColors.delayed
                          : VeraProbColors.critical,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: VeraProbSpacing.sm),
              Text(
                '${activePercent.toStringAsFixed(1)}%',
                style: VeraProbTypography.bodyMedium.copyWith(
                  color: VeraProbColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final IconData icon;

  const _StatusChip({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VeraProbSpacing.sm,
        vertical: VeraProbSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: VeraProbTypography.kpiValue.copyWith(
              fontSize: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: VeraProbTypography.kpiLabel.copyWith(
              color: color.withValues(alpha: 0.8),
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
