import 'package:flutter/material.dart';

import 'package:veraprob/application/sla_audit/rule_version_history_entry.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';

/// Collapsible financial impact simulation panel shown in the Rule Edit Dialog.
class RuleImpactSimulationPanel extends StatelessWidget {
  const RuleImpactSimulationPanel({
    super.key,
    required this.ruleType,
    required this.currentRule,
    required this.controllers,
    required this.expanded,
    required this.onToggle,
  });

  final SlaRuleType ruleType;
  final RuleVersionHistoryEntry? currentRule;
  final Map<String, TextEditingController> controllers;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: VeraProbRadii.mdAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(
                    Icons.insights_outlined,
                    size: 16,
                    color: VeraProbColors.secondary,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Simulação de Impacto Financeiro',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: VeraProbColors.secondary,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: VeraProbColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _ImpactBody(
                ruleType: ruleType,
                currentRule: currentRule,
                controllers: controllers,
              ),
            ),
        ],
      ),
    );
  }
}

class _ImpactBody extends StatelessWidget {
  const _ImpactBody({
    required this.ruleType,
    required this.currentRule,
    required this.controllers,
  });

  final SlaRuleType ruleType;
  final RuleVersionHistoryEntry? currentRule;
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    if (currentRule == null) {
      return const Text(
        'Configure e salve a primeira versão da regra para habilitar simulações comparativas.',
        style: TextStyle(fontSize: 12, color: VeraProbColors.textSecondary),
      );
    }

    final rows = _buildImpactRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: VeraProbColors.border, height: 1),
        const SizedBox(height: 10),
        const Text(
          'Alteração de Parâmetro',
          style: TextStyle(
            fontSize: 11,
            color: VeraProbColors.textDisabled,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        ...rows,
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: VeraProbColors.warning.withValues(alpha: 0.08),
            borderRadius: VeraProbRadii.mdAll,
          ),
          child: const Row(
            children: [
              Icon(
                Icons.warning_amber_outlined,
                size: 12,
                color: VeraProbColors.warning,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Simulação qualitativa — impacto quantitativo disponível na Phase 7 (Audit Exports).',
                  style: TextStyle(
                    fontSize: 11,
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildImpactRows() {
    final c = currentRule!.config;
    return switch (ruleType.value) {
      'MAX_TOLERANCE_DELAY' => [
        _ImpactRow(
          label: 'Tolerância',
          current: '${c['threshold_minutes']} min',
          proposed: '${controllers['threshold_minutes']!.text} min',
          impactWhenIncreased: 'Menos penalidades — mais leniente com atrasos',
          impactWhenDecreased: 'Mais penalidades — penaliza atrasos menores',
          currentValue: (c['threshold_minutes'] as num?)?.toDouble() ?? 0,
          proposedText: controllers['threshold_minutes']!.text,
        ),
      ],
      'MAX_EVIDENCE_GAP' => [
        _ImpactRow(
          label: 'Lacuna máx.',
          current: '${c['max_gap_seconds']} s',
          proposed: '${controllers['max_gap_seconds']!.text} s',
          impactWhenIncreased: 'Mais permissivo com lacunas de telemetria',
          impactWhenDecreased:
              'Invalida mais evidências — pode aumentar no-shows',
          currentValue: (c['max_gap_seconds'] as num?)?.toDouble() ?? 0,
          proposedText: controllers['max_gap_seconds']!.text,
        ),
      ],
      'MIN_GEOFENCE_COVERAGE' => [
        _ImpactRow(
          label: 'Permanência mín.',
          current: '${c['min_dwell_seconds']} s',
          proposed: '${controllers['min_dwell_seconds']!.text} s',
          impactWhenIncreased: 'Exigência maior — mais viagens rejeitadas',
          impactWhenDecreased: 'Exigência menor — mais viagens validadas',
          currentValue: (c['min_dwell_seconds'] as num?)?.toDouble() ?? 0,
          proposedText: controllers['min_dwell_seconds']!.text,
        ),
      ],
      'NO_SHOW_PENALTY' => [
        _ImpactRow(
          label: 'Penalidade',
          current:
              'R\$ ${(((c['penalty_amount_cents'] as int?) ?? 0) / 100).toStringAsFixed(2)}',
          proposed: 'R\$ ${controllers['penalty_amount_cents']!.text}',
          impactWhenIncreased: 'Maior recuperação financeira por no-show',
          impactWhenDecreased: 'Menor recuperação financeira por no-show',
          currentValue:
              ((c['penalty_amount_cents'] as num?)?.toDouble() ?? 0) / 100,
          proposedText: controllers['penalty_amount_cents']!.text,
        ),
      ],
      _ => [],
    };
  }
}

class _ImpactRow extends StatelessWidget {
  const _ImpactRow({
    required this.label,
    required this.current,
    required this.proposed,
    required this.impactWhenIncreased,
    required this.impactWhenDecreased,
    required this.currentValue,
    required this.proposedText,
  });

  final String label;
  final String current;
  final String proposed;
  final String impactWhenIncreased;
  final String impactWhenDecreased;
  final double currentValue;
  final String proposedText;

  @override
  Widget build(BuildContext context) {
    final proposedValue = double.tryParse(proposedText) ?? currentValue;
    final delta = proposedValue - currentValue;
    final unchanged = delta.abs() < 0.001;

    final impactText = unchanged
        ? 'Sem alteração'
        : delta > 0
        ? impactWhenIncreased
        : impactWhenDecreased;

    final impactColor = unchanged
        ? VeraProbColors.textDisabled
        : delta > 0
        ? VeraProbColors.warning
        : VeraProbColors.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      current,
                      style: const TextStyle(
                        fontSize: 13,
                        color: VeraProbColors.textSecondary,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_right_alt,
                      size: 14,
                      color: VeraProbColors.textDisabled,
                    ),
                    Text(
                      proposed,
                      style: const TextStyle(
                        fontSize: 13,
                        color: VeraProbColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              impactText,
              textAlign: TextAlign.end,
              style: TextStyle(fontSize: 11, color: impactColor),
            ),
          ),
        ],
      ),
    );
  }
}
