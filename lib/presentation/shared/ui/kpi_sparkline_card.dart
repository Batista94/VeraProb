import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/presentation/shared/ui/sparkline_widget.dart';

/// CFO-grade KPI card: icon + title + primary value + sparkline trend.
///
/// Consumes a raw `List<int>` series (cents or bps — any int domain)
/// so the card is decoupled from any specific query service.
/// The [percentageBps] badge is optional (omit for absolute cards like
/// "Total Contratado" which have no comparative denominator).
class KpiSparklineCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final List<int> sparklineSeries;
  final int? percentageBps;
  final VoidCallback? onTap;

  const KpiSparklineCard({
    super.key,
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    required this.sparklineSeries,
    this.percentageBps,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: VeraProbRadii.xlAll,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: VeraProbColors.surface,
          borderRadius: VeraProbRadii.xlAll,
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        ),
        child: ClipRect(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: icon + title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: VeraProbRadii.mdAll,
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      style: VeraProbTypography.kpiLabel.copyWith(
                        letterSpacing: 1.0,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: VeraProbSpacing.sm),
              // Value + optional percentage badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: VeraProbTypography.kpiValue.copyWith(
                        color: color,
                        fontSize: 26,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (percentageBps != null) ...[
                    const SizedBox(width: VeraProbSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: VeraProbRadii.lgAll,
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${(percentageBps! / 100).toStringAsFixed(1)}%',
                        style: VeraProbTypography.badge.copyWith(
                          color: color,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: VeraProbSpacing.sm),
              // Sparkline trend
              SparklineWidget(
                values: sparklineSeries.isEmpty ? [0, 0] : sparklineSeries,
                color: color,
                height: 22,
                strokeWidth: 1.5,
              ),
              if (onTap != null) ...[
                const SizedBox(height: VeraProbSpacing.xs),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.open_in_new,
                      size: 12,
                      color: VeraProbColors.textSecondary,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ), // ClipRect
      ),
    );
  }
}
