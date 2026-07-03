import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// A premium, consistent chip for status and types.
///
/// Replaces ad-hoc Containers for badges/chips across the app.
class VeraProbChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool outline;

  const VeraProbChip({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.outline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VeraProbSpacing.sm,
        vertical: VeraProbSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : color.withValues(alpha: 0.12),
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(
          color: color.withValues(alpha: outline ? 0.6 : 0.3),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 6),
          ],
          Text(label, style: VeraProbTypography.badge.copyWith(color: color)),
        ],
      ),
    );
  }
}
