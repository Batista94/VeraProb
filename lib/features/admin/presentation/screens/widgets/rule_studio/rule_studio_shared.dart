import 'package:flutter/material.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// Shared icon widget for rule type visualization used across Rule Studio.
class RuleTypeIcon extends StatelessWidget {
  const RuleTypeIcon({super.key, required this.ruleType, this.size = 20});

  final SlaRuleType ruleType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (ruleType.value) {
      'MAX_TOLERANCE_DELAY' => (
        Icons.schedule_outlined,
        VeraProbColors.warning,
      ),
      'MAX_EVIDENCE_GAP' => (
        Icons.signal_cellular_connected_no_internet_0_bar,
        VeraProbColors.info,
      ),
      'MIN_GEOFENCE_COVERAGE' => (
        Icons.location_on_outlined,
        VeraProbColors.onTime,
      ),
      'NO_SHOW_PENALTY' => (Icons.money_off_outlined, VeraProbColors.error),
      _ => (Icons.rule_outlined, VeraProbColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: size, color: color),
    );
  }
}

/// Shared parameter input field used in the rule edit dialog.
class RuleParamField extends StatelessWidget {
  const RuleParamField({
    super.key,
    required this.label,
    required this.hint,
    required this.controller,
    required this.inputType,
    required this.helpText,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType inputType;
  final String helpText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: VeraProbColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: inputType,
          style: const TextStyle(color: VeraProbColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: VeraProbColors.textDisabled),
            filled: true,
            fillColor: VeraProbColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: VeraProbColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: VeraProbColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: VeraProbColors.primary),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          helpText,
          style: const TextStyle(
            fontSize: 11,
            color: VeraProbColors.textDisabled,
          ),
        ),
      ],
    );
  }
}

/// Returns a human-readable label for a given [SlaRuleType].
String ruleTypeLabel(SlaRuleType type) => switch (type.value) {
  'MAX_TOLERANCE_DELAY' => 'Tolerância de Atraso',
  'MAX_EVIDENCE_GAP' => 'Lacuna de Evidência',
  'MIN_GEOFENCE_COVERAGE' => 'Permanência Mínima no Geofence',
  'NO_SHOW_PENALTY' => 'Penalidade No-Show',
  _ => type.value,
};
