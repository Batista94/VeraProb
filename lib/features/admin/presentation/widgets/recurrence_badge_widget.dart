import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../domain/sla_audit/infraction_recurrence_report.dart';

/// Displays the monthly recurrence context for a vehicle infraction.
///
/// Shows the ordinal count badge ("Xª infração no mês") and a mini-timeline
/// of prior infraction dots, making repeat offender patterns immediately
/// visible to the auditor (INV-23 — provenance in ≤1 click).
class RecurrenceBadgeWidget extends StatelessWidget {
  final InfractionRecurrenceReport report;

  const RecurrenceBadgeWidget({super.key, required this.report});

  Color _badgeColor() {
    final n = report.infractionNumberThisMonth;
    if (n >= 3) return VeraProbColors.error;
    if (n == 2) return VeraProbColors.warning;
    return VeraProbColors.success;
  }

  String _ordinal(int n) => '$nª';

  @override
  Widget build(BuildContext context) {
    final badgeColor = _badgeColor();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ────────────────────────────────────────────────
        Row(
          children: [
            const Icon(
              Icons.repeat_rounded,
              size: 14,
              color: VeraProbColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              'REINCIDÊNCIA MENSAL',
              style: VeraProbTypography.caption.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const Spacer(),
            // Ordinal badge chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: badgeColor.withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                '${_ordinal(report.infractionNumberThisMonth)} infração no mês',
                style: VeraProbTypography.badge.copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        // ── Mini-timeline dots ─────────────────────────────────────────
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Prior infractions (smaller dots)
            for (final dot in report.priorInfractions)
              _InfractionDot(dot: dot, isCurrent: false),
            // Current infraction (larger, highlighted)
            _InfractionDot(
              dot: PriorInfractionDot(
                occurredAtUtc: DateTime.now().toUtc(),
                clauseRef: report.priorInfractions.isNotEmpty
                    ? report.priorInfractions.last.clauseRef
                    : 'ATUAL',
              ),
              isCurrent: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _InfractionDot extends StatelessWidget {
  final PriorInfractionDot dot;
  final bool isCurrent;

  const _InfractionDot({required this.dot, required this.isCurrent});

  Color _dotColor() {
    final prefix = dot.clauseRef.split('-').first.toUpperCase();
    return switch (prefix) {
      'VEL' => VeraProbColors.warning,
      'ABR' => VeraProbColors.warning,
      _ => VeraProbColors.error,
    };
  }

  String _formatDate(DateTime utc) {
    final local = utc.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final color = isCurrent ? VeraProbColors.error : _dotColor();
    final size = isCurrent ? 12.0 : 8.0;
    final label = isCurrent
        ? 'Atual'
        : '${dot.clauseRef} — ${_formatDate(dot.occurredAtUtc)}';

    return Tooltip(
      message: label,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: isCurrent ? 1.0 : 0.7),
          shape: BoxShape.circle,
          border: isCurrent
              ? Border.all(color: color, width: 1.5)
              : null,
        ),
      ),
    );
  }
}
