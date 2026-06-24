import 'package:flutter/material.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Individual vehicle/device health card for the Ingestion Health grid.
///
/// Shows plate (or 'N/D' for phantoms), hardware status icon, gap duration,
/// integrity score bar, and anomaly badge.
class VehicleHealthCard extends StatelessWidget {
  final VehicleHealthEntry entry;
  final bool isSelected;
  final VoidCallback onTap;

  const VehicleHealthCard({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = _colorForStatus(entry.hardwareStatus);
    // Physical Metric - Double Required
    final scorePercent = entry.integrityScoreBps / 100.0;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: VeraProbSpacing.cardPadding,
        decoration: BoxDecoration(
          color: isSelected
              ? VeraProbColors.surfaceElevated
              : VeraProbColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? VeraProbColors.primary.withValues(alpha: 0.5)
                : VeraProbColors.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            // Status icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _iconForStatus(entry.hardwareStatus),
                color: statusColor,
                size: 20,
              ),
            ),
            const SizedBox(width: VeraProbSpacing.sm),

            // Plate + model
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.displayPlate,
                          style: VeraProbTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isPhantom) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: VeraProbColors.secondary.withValues(
                              alpha: 0.2,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'FANTASMA',
                            style: VeraProbTypography.kpiLabel.copyWith(
                              fontSize: 8,
                              color: VeraProbColors.secondary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entry.hardwareStatus.label,
                    style: VeraProbTypography.kpiLabel.copyWith(
                      color: statusColor,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),

            // Gap duration
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatGap(entry.gapSeconds),
                  style: VeraProbTypography.bodyMedium.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                // Integrity score bar
                SizedBox(
                  width: 60,
                  child: Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: (entry.integrityScoreBps / 10000.0).clamp(
                              0.0,
                              1.0,
                            ),
                            backgroundColor: VeraProbColors.surfaceElevated,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _colorForScore(entry.integrityScoreBps),
                            ),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '${scorePercent.toStringAsFixed(0)}%',
                        style: VeraProbTypography.kpiLabel.copyWith(
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Anomaly badge
            if (entry.anomalyCount24h > 0) ...[
              const SizedBox(width: VeraProbSpacing.sm),
              Tooltip(
                message: '${entry.anomalyCount24h} anomalias nas últimas 24h',
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: VeraProbColors.critical.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 12,
                        color: VeraProbColors.critical,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${entry.anomalyCount24h}',
                        style: VeraProbTypography.kpiLabel.copyWith(
                          color: VeraProbColors.critical,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _colorForStatus(HardwareStatusView status) => switch (status) {
    HardwareStatusView.healthy => VeraProbColors.onTime,
    HardwareStatusView.delayed => VeraProbColors.delayed,
    HardwareStatusView.offline => VeraProbColors.critical,
    HardwareStatusView.neverSeen => VeraProbColors.neutral,
  };

  static IconData _iconForStatus(HardwareStatusView status) => switch (status) {
    HardwareStatusView.healthy => Icons.check_circle_outline,
    HardwareStatusView.delayed => Icons.schedule_outlined,
    HardwareStatusView.offline => Icons.signal_wifi_off_outlined,
    HardwareStatusView.neverSeen => Icons.device_unknown_outlined,
  };

  static Color _colorForScore(int bps) {
    if (bps >= 7000) return VeraProbColors.onTime;
    if (bps >= 4000) return VeraProbColors.delayed;
    return VeraProbColors.critical;
  }

  static String _formatGap(int seconds) {
    if (seconds >= 999999) return '—';
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    return '${hours}h ${minutes}m';
  }
}
