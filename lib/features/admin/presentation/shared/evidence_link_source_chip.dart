import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';

/// Badge indicating how an evidence was linked to an execution.
///
/// Forensic transparency: supervisors need to distinguish system-linked
/// evidence from driver-initiated links during fraud audits.
class EvidenceLinkSourceChip extends StatelessWidget {
  final String source;

  const EvidenceLinkSourceChip({super.key, required this.source});

  static const _map = <String, ({String emoji, String label, Color color})>{
    'telegram': (emoji: '🤖', label: 'Auto', color: VeraProbColors.onTime),
    'telegram_self_link': (
      emoji: '🧑‍✈️',
      label: 'Vinculado pelo Condutor',
      color: VeraProbColors.info,
    ),
    'reconciliation': (
      emoji: '🔗',
      label: 'Reconciliação',
      color: VeraProbColors.neutral,
    ),
    'reconciliation_shortcut': (
      emoji: '⚡',
      label: 'Quick Link',
      color: VeraProbColors.neutral,
    ),
    'manual': (emoji: '✏️', label: 'Manual', color: VeraProbColors.warning),
  };

  @override
  Widget build(BuildContext context) {
    final entry = _map[source];
    final emoji = entry?.emoji ?? '❓';
    final label = entry?.label ?? source;
    final color = entry?.color ?? VeraProbColors.neutral;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: VeraProbRadii.smAll,
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

  /// Returns the label for a source key (used in PDF/non-widget contexts).
  static String labelFor(String source) {
    final entry = _map[source];
    return entry != null ? '${entry.emoji} ${entry.label}' : source;
  }
}
