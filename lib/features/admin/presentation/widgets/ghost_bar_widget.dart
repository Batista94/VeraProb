import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Visual overlay replacing the text-only infraction summary columns (Zona 3).
///
/// Left column: DIFERENÇA OBSERVADA — foreground bar shows the violation
/// magnitude against the tolerance budget (grey ghost bar).
///
/// Right column: LIMITE CONTRATUAL — full-width grey bar anchors the scale.
///
/// INV-4: No domain logic. INV-23: Auditor can read violation severity at a
/// glance without needing to mentally compare two numbers.
class GhostBarWidget extends StatelessWidget {
  final double deltaValue;
  final double thresholdValue;
  final String unit;
  final String clauseRef;

  const GhostBarWidget({
    super.key,
    required this.deltaValue,
    required this.thresholdValue,
    required this.unit,
    required this.clauseRef,
  });

  Color _foregroundColor() {
    final prefix = clauseRef.split('-').first.toUpperCase();
    return switch (prefix) {
      'VEL' => VeraProbColors.warning,
      'ABR' => VeraProbColors.warning,
      _ => VeraProbColors.error,
    };
  }

  @override
  Widget build(BuildContext context) {
    final fgColor = _foregroundColor();
    final total = (thresholdValue + deltaValue) == 0.0
        ? 1.0
        : thresholdValue + deltaValue;

    return Row(
      children: [
        Expanded(
          child: _GhostColumn(
            label: 'DIFERENÇA OBSERVADA',
            value: '${deltaValue.toStringAsFixed(1)} $unit',
            barFraction: (deltaValue / total).clamp(0.0, 1.0),
            foregroundColor: fgColor,
            isThreshold: false,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _GhostColumn(
            label: 'LIMITE CONTRATUAL',
            value: '${thresholdValue.toStringAsFixed(1)} $unit',
            barFraction: 1.0,
            foregroundColor: VeraProbColors.textDisabled,
            isThreshold: true,
          ),
        ),
      ],
    );
  }
}

class _GhostColumn extends StatelessWidget {
  final String label;
  final String value;
  final double barFraction;
  final Color foregroundColor;
  final bool isThreshold;

  const _GhostColumn({
    required this.label,
    required this.value,
    required this.barFraction,
    required this.foregroundColor,
    required this.isThreshold,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: VeraProbTypography.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (_, constraints) {
            final totalWidth = constraints.maxWidth;
            final barWidth = isThreshold
                ? totalWidth
                : (totalWidth * barFraction).clamp(4.0, totalWidth);

            return SizedBox(
              height: 8,
              child: Stack(
                children: [
                  // Ghost (budget) bar — always full width
                  Container(
                    width: totalWidth,
                    height: 8,
                    decoration: BoxDecoration(
                      color: VeraProbColors.textDisabled.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  // Foreground bar — violation magnitude
                  Container(
                    width: barWidth,
                    height: 8,
                    decoration: BoxDecoration(
                      color: foregroundColor.withValues(
                        alpha: isThreshold ? 0.4 : 0.85,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: VeraProbTypography.dataValue.copyWith(color: foregroundColor),
        ),
      ],
    );
  }
}
