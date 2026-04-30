import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

class OrgStatusBadge extends StatelessWidget {
  final String? label;
  const OrgStatusBadge({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = _resolve(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label ?? '—',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  (Color, IconData?) _resolve(String? lbl) {
    switch (lbl) {
      case 'Ativo':
        return (VeraProbColors.success, null);
      case 'Trial':
        return (VeraProbColors.info, null);
      case 'Suspenso':
        return (VeraProbColors.delayed, Icons.pause_circle_outline);
      case 'Churned':
        return (VeraProbColors.warning, Icons.cancel_outlined);
      case 'Arquivado':
        return (Colors.amber, Icons.lock_outline);
      case 'Excluído':
        return (VeraProbColors.error, Icons.delete_outline);
      default:
        return (VeraProbColors.textSecondary, null);
    }
  }
}

class PlanBadge extends StatelessWidget {
  final String? planType;
  const PlanBadge({super.key, this.planType});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: VeraProbColors.secondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        planType?.toUpperCase() ?? '—',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: VeraProbColors.secondary,
        ),
      ),
    );
  }
}
