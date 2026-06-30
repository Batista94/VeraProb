import 'package:flutter/material.dart';

import 'package:veraprob/application/sla_audit/projections/fleet_health_view.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/widgets/health_display_helpers.dart';

class VehicleHealthCard extends StatefulWidget {
  final VehicleHealthEntry entry;
  final bool isSelected;
  final bool isPreselected;
  final VoidCallback onTap;

  const VehicleHealthCard({
    super.key,
    required this.entry,
    required this.isSelected,
    required this.isPreselected,
    required this.onTap,
  });

  @override
  State<VehicleHealthCard> createState() => _VehicleHealthCardState();
}

class _VehicleHealthCardState extends State<VehicleHealthCard>
    with SingleTickerProviderStateMixin {
  static final _kPulseColor = VeraProbColors.delayed.withValues(alpha: 0.3);

  late final AnimationController _pulseController;
  late final Animation<Color?> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulseAnimation = TweenSequence<Color?>([
      TweenSequenceItem(
        tween: ColorTween(
          begin: Colors.transparent,
          end: _kPulseColor,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ColorTween(
          begin: _kPulseColor,
          end: Colors.transparent,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 80,
      ),
    ]).animate(_pulseController);
    if (widget.isPreselected) _pulseController.forward();
  }

  @override
  void didUpdateWidget(VehicleHealthCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isPreselected && widget.isPreselected) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = HealthDisplayHelpers.colorForStatus(
      widget.entry.hardwareStatus,
    );
    // Physical Metric - Double Required
    final scorePercent = widget.entry.integrityScoreBps / 100.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: VeraProbSpacing.cardPadding,
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? VeraProbColors.surfaceElevated
                  : VeraProbColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.isSelected
                    ? VeraProbColors.primary.withValues(alpha: 0.5)
                    : VeraProbColors.border,
                width: widget.isSelected ? 1.5 : 1.0,
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
                    _iconForStatus(widget.entry.hardwareStatus),
                    color: statusColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: VeraProbSpacing.sm),

                // Plate + status label
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.entry.displayPlate,
                              style: VeraProbTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (widget.entry.isPhantom) ...[
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
                        widget.entry.hardwareStatus.label,
                        style: VeraProbTypography.kpiLabel.copyWith(
                          color: statusColor,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),

                // Gap + score bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      HealthDisplayHelpers.formatGap(widget.entry.gapSeconds),
                      style: VeraProbTypography.bodyMedium.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      width: 60,
                      child: Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value:
                                    (widget.entry.integrityScoreBps / 10000.0)
                                        .clamp(0.0, 1.0),
                                backgroundColor: VeraProbColors.surfaceElevated,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  HealthDisplayHelpers.colorForScore(
                                    widget.entry.integrityScoreBps,
                                  ),
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
                if (widget.entry.anomalyCount24h > 0) ...[
                  const SizedBox(width: VeraProbSpacing.sm),
                  Tooltip(
                    message:
                        '${widget.entry.anomalyCount24h} anomalias nas últimas 24h',
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
                            '${widget.entry.anomalyCount24h}',
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

          // One-shot amber landing pulse (only for drill-down preselection)
          if (widget.isPreselected)
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, _) => Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: _pulseAnimation.value,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static IconData _iconForStatus(HardwareStatusView status) => switch (status) {
    HardwareStatusView.healthy => Icons.check_circle_outline,
    HardwareStatusView.delayed => Icons.schedule_outlined,
    HardwareStatusView.offline => Icons.signal_wifi_off_outlined,
    HardwareStatusView.neverSeen => Icons.device_unknown_outlined,
  };
}
