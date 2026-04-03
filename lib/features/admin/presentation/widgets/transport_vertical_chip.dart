import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// Compact badge chip displaying the transport vertical with icon and color.
class TransportVerticalChip extends StatelessWidget {
  final TransportVertical vertical;

  const TransportVerticalChip({super.key, required this.vertical});

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(vertical);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_iconFor(vertical), size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            vertical.label,
            style: VeraProbTypography.badge.copyWith(
              color: color,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  static Color _colorFor(TransportVertical v) => switch (v) {
    TransportVertical.fretamento => VeraProbColors.primary,
    TransportVertical.cargaSeca => VeraProbColors.delayed,
    TransportVertical.cargaRefrigerada => VeraProbColors.scheduled,
    TransportVertical.transferenciaFuncionarios => VeraProbColors.secondary,
    TransportVertical.escolar => VeraProbColors.onTime,
    TransportVertical.custom => VeraProbColors.neutral,
  };

  static IconData _iconFor(TransportVertical v) => switch (v) {
    TransportVertical.fretamento => Icons.directions_bus_outlined,
    TransportVertical.cargaSeca => Icons.local_shipping_outlined,
    TransportVertical.cargaRefrigerada => Icons.ac_unit_outlined,
    TransportVertical.transferenciaFuncionarios => Icons.groups_outlined,
    TransportVertical.escolar => Icons.school_outlined,
    TransportVertical.custom => Icons.tune_outlined,
  };
}
