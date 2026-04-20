import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// Ingestion Health Widget — visual 'at-a-glance' view of telemetry gaps.
///
/// Displays:
/// 1. An integrity score badge with color-coded severity.
/// 2. A timeline bar showing clean signal (green) vs Data Silence gaps (red).
/// 3. A gap summary list with timestamps and durations.
///
/// Links to WS-1 Double Confirmation: when [report.requiresDoubleConfirmation],
/// the badge renders in error color to signal the auditor.
class IngestionHealthWidget extends StatelessWidget {
  /// The signal integrity report to visualize.
  final SignalIntegrityReport report;

  /// Optional callback when the auditor taps on a specific gap.
  final ValueChanged<DataSilenceGap>? onGapTap;

  const IngestionHealthWidget({super.key, required this.report, this.onGapTap});

  Color _scoreColor(int score) {
    if (score >= 90) return VeraProbColors.success;
    if (score >= 70) return VeraProbColors.warning;
    return VeraProbColors.error;
  }

  String _severityLabel(GapSeverity severity) {
    switch (severity) {
      case GapSeverity.warning:
        return 'ALERTA';
      case GapSeverity.critical:
        return 'CRÍTICO';
    }
  }

  IconData _severityIcon(GapSeverity severity) {
    switch (severity) {
      case GapSeverity.warning:
        return Icons.warning_amber_rounded;
      case GapSeverity.critical:
        return Icons.error_rounded;
    }
  }

  String _formatTime(DateTime utc) {
    final local = utc.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    if (seconds >= 3600) {
      final h = seconds ~/ 3600;
      final m = (seconds % 3600) ~/ 60;
      return '${h}h ${m}min';
    }
    if (seconds >= 60) {
      final m = seconds ~/ 60;
      final s = seconds % 60;
      return '${m}min ${s}s';
    }
    return '${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final color = _scoreColor(report.integrityScore);
    final hasGaps = report.gaps.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Header: Score + Label ──────────────────────────────────────
        Row(
          children: [
            Icon(
              hasGaps
                  ? Icons.signal_cellular_connected_no_internet_4_bar_rounded
                  : Icons.signal_cellular_alt_rounded,
              size: 14,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              'INTEGRIDADE DO SINAL',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.textSecondary,
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${report.integrityScore}%',
                style: VeraProbTypography.badge.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),

        if (report.totalSpanSeconds > 0) ...[
          const SizedBox(height: 8),

          // ── Timeline Bar ──────────────────────────────────────────────
          Tooltip(
            message:
                '${report.totalSilentSeconds}s de silêncio em ${report.totalSpanSeconds}s',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: hasGaps
                    ? CustomPaint(
                        size: const Size(double.infinity, 6),
                        painter: _TimelineBarPainter(
                          report: report,
                          cleanColor: VeraProbColors.success,
                          gapWarningColor: VeraProbColors.warning,
                          gapCriticalColor: VeraProbColors.error,
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: VeraProbColors.success.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
              ),
            ),
          ),
        ],

        // ── Gap List ────────────────────────────────────────────────────
        if (hasGaps) ...[
          const SizedBox(height: 8),
          ...report.gaps.map(
            (gap) => _GapRow(
              gap: gap,
              severityLabel: _severityLabel(gap.severity),
              severityIcon: _severityIcon(gap.severity),
              formattedStart: _formatTime(gap.startedAtUtc),
              formattedEnd: _formatTime(gap.endedAtUtc),
              formattedDuration: _formatDuration(gap.durationSeconds),
              onTap: onGapTap != null ? () => onGapTap!(gap) : null,
            ),
          ),
        ],
      ],
    );
  }
}

/// Custom painter that renders a horizontal timeline bar showing clean vs
/// silent segments.
class _TimelineBarPainter extends CustomPainter {
  final SignalIntegrityReport report;
  final Color cleanColor;
  final Color gapWarningColor;
  final Color gapCriticalColor;

  const _TimelineBarPainter({
    required this.report,
    required this.cleanColor,
    required this.gapWarningColor,
    required this.gapCriticalColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (report.totalSpanSeconds <= 0) return;

    // Paint clean background
    final bgPaint = Paint()..color = cleanColor.withValues(alpha: 0.3);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    final totalSpan = report.totalSpanSeconds.toDouble();

    // Derive approximate stream start from the last gap's end and total span.
    final streamEnd = report.gaps.last.endedAtUtc;
    final streamStart = streamEnd.subtract(
      Duration(seconds: totalSpan.round()),
    );

    for (final gap in report.gaps) {
      final gapColor = gap.severity == GapSeverity.critical
          ? gapCriticalColor
          : gapWarningColor;

      final gapPaint = Paint()..color = gapColor.withValues(alpha: 0.8);

      final gapFraction = gap.durationSeconds / totalSpan;
      final gapWidth = gapFraction * size.width;

      // Position relative to stream start
      final offsetSeconds = gap.startedAtUtc.difference(streamStart).inSeconds;
      final x = (offsetSeconds / totalSpan).clamp(0.0, 1.0) * size.width;

      canvas.drawRect(Rect.fromLTWH(x, 0, gapWidth, size.height), gapPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TimelineBarPainter oldDelegate) =>
      report != oldDelegate.report;
}

/// Individual gap row in the health widget.
class _GapRow extends StatelessWidget {
  final DataSilenceGap gap;
  final String severityLabel;
  final IconData severityIcon;
  final String formattedStart;
  final String formattedEnd;
  final String formattedDuration;
  final VoidCallback? onTap;

  const _GapRow({
    required this.gap,
    required this.severityLabel,
    required this.severityIcon,
    required this.formattedStart,
    required this.formattedEnd,
    required this.formattedDuration,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCritical = gap.severity == GapSeverity.critical;
    final color = isCritical ? VeraProbColors.error : VeraProbColors.warning;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Icon(severityIcon, size: 12, color: color),
              const SizedBox(width: 6),
              Text(
                severityLabel,
                style: VeraProbTypography.badge.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 8,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$formattedStart → $formattedEnd',
                  style: TextStyle(
                    fontSize: 10,
                    color: VeraProbColors.textSecondary,
                    fontFamily: VeraProbTypography.kpiValue.fontFamily,
                  ),
                ),
              ),
              Text(
                formattedDuration,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
