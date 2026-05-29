import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Semantic badge for evidence categories assigned via Telegram inline keyboard.
///
/// Maps each category key to an emoji, label, and color from the design system.
/// Null category renders a neutral "Sem tag" chip.
class EvidenceCategoryChip extends StatelessWidget {
  final String? category;

  const EvidenceCategoryChip({super.key, required this.category});

  static const _map = <String, ({String emoji, String label, Color color})>{
    'incidente': (
      emoji: '🚨',
      label: 'Incidente',
      color: VeraProbColors.critical,
    ),
    'oper': (emoji: '🛠️', label: 'Operacional', color: VeraProbColors.delayed),
    'estado': (emoji: '📸', label: 'Estado', color: VeraProbColors.onTime),
    'doc': (emoji: '📑', label: 'Documental', color: VeraProbColors.info),
    // textSecondary, not neutral: #64748B fails WCAG AA (2.72:1) as chip text.
    'outros': (
      emoji: '🔍',
      label: 'Outros',
      color: VeraProbColors.textSecondary,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final entry = _map[category];
    final emoji = entry?.emoji ?? '—';
    final label = entry?.label ?? 'Sem tag';
    final color = entry?.color ?? VeraProbColors.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$emoji $label',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// Returns the emoji+label for a category key (used in PDF/non-widget contexts).
  static String labelFor(String? category) {
    final entry = _map[category];
    return entry != null ? '${entry.emoji} ${entry.label}' : '— Sem tag';
  }

  /// Sort priority: incidente=0 (first), null=5 (last).
  static int sortPriority(String? category) {
    return switch (category) {
      'incidente' => 0,
      'oper' => 1,
      'estado' => 2,
      'doc' => 3,
      'outros' => 4,
      _ => 5,
    };
  }
}
