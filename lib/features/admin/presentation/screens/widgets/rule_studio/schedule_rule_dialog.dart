import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/sla_audit/rule_version_history_entry.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/rule_studio_providers.dart';

import 'rule_studio_impact_panel.dart';
import 'rule_studio_shared.dart';

final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

/// Single numeric parameter that defines a schedulable rule version, plus the
/// labels/help shown in the dialog. `null` for rule types the scheduler does
/// not support (e.g. list-based REQUIRED_EVIDENCE).
class RuleScheduleParam {
  final String configKey;
  final String label;
  final String hint;
  final String help;

  const RuleScheduleParam({
    required this.configKey,
    required this.label,
    required this.hint,
    required this.help,
  });
}

RuleScheduleParam? ruleScheduleParamFor(SlaRuleType type) => switch (type) {
  SlaRuleType.maxToleranceDelay => const RuleScheduleParam(
    configKey: 'threshold_minutes',
    label: 'Tolerância de atraso (min)',
    hint: 'ex.: 15',
    help: 'Atrasos acima deste limite geram penalidade.',
  ),
  SlaRuleType.maxEvidenceGap => const RuleScheduleParam(
    configKey: 'max_gap_seconds',
    label: 'Lacuna máxima de evidência (s)',
    hint: 'ex.: 120',
    help: 'Lacunas de telemetria acima disso invalidam a evidência.',
  ),
  SlaRuleType.minGeofenceCoverage => const RuleScheduleParam(
    configKey: 'min_dwell_seconds',
    label: 'Permanência mínima no geofence (s)',
    hint: 'ex.: 60',
    help: 'Tempo mínimo dentro da zona para validar a parada.',
  ),
  SlaRuleType.noShowPenalty => const RuleScheduleParam(
    configKey: 'penalty_amount_cents',
    label: 'Penalidade No-Show (centavos)',
    hint: 'ex.: 50000 = R\$ 500,00',
    help: 'Valor em centavos aplicado a cada No-Show.',
  ),
  _ => null,
};

/// Whether the scheduler supports creating a future version of [type].
bool ruleTypeSupportsScheduling(SlaRuleType type) =>
    ruleScheduleParamFor(type) != null;

/// Dialog to schedule a FUTURE version of an existing contractual rule.
/// Composes [RuleParamField] + [RuleImpactSimulationPanel]; on confirm it calls
/// [scheduleContractualRule] (org/role/session resolved server-aware, INV-1).
class ScheduleRuleDialog extends ConsumerStatefulWidget {
  final String contractId;
  final SlaRuleType ruleType;
  final RuleVersionHistoryEntry? currentRule;

  const ScheduleRuleDialog({
    super.key,
    required this.contractId,
    required this.ruleType,
    required this.currentRule,
  });

  @override
  ConsumerState<ScheduleRuleDialog> createState() => _ScheduleRuleDialogState();
}

class _ScheduleRuleDialogState extends ConsumerState<ScheduleRuleDialog> {
  late final RuleScheduleParam _param;
  late final Map<String, TextEditingController> _controllers;
  late DateTime _effectiveAt;
  bool _impactExpanded = false;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _param = ruleScheduleParamFor(widget.ruleType)!;
    final current = widget.currentRule?.config[_param.configKey];
    _controllers = {
      _param.configKey: TextEditingController(
        text: current == null ? '' : '$current',
      ),
    };
    // Live impact preview: rebuild as the operator edits the parameter.
    _controllers[_param.configKey]!.addListener(_onParamChanged);
    _effectiveAt = DateTime.now().toUtc().add(const Duration(days: 1));
  }

  void _onParamChanged() {
    if (_impactExpanded) setState(() {});
  }

  @override
  void dispose() {
    _controllers[_param.configKey]!.removeListener(_onParamChanged);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now().toUtc().toLocal();
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveAt.toLocal(),
      firstDate: now,
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null) return;
    final local = _effectiveAt.toLocal();
    setState(() {
      _effectiveAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        local.hour,
        local.minute,
      ).toUtc();
    });
  }

  Future<void> _submit() async {
    if (_isSaving) return;
    final raw = _controllers[_param.configKey]!.text.trim();
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      setState(() => _error = 'Informe um valor numérico válido.');
      return;
    }

    // Lesson 8: capture context-bound objects before the first await.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final error = await scheduleContractualRule(
      ref,
      contractId: widget.contractId,
      oldRuleId: widget.currentRule?.id,
      ruleType: widget.ruleType,
      newConfig: {_param.configKey: value},
      evaluationOrder: widget.currentRule?.evaluationOrder ?? 0,
      effectiveAtUtc: _effectiveAt,
    );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _isSaving = false;
        _error = error;
      });
      return;
    }

    ref.invalidate(ruleHistoryProvider(widget.contractId));
    ref.invalidate(activeRulesProvider(widget.contractId));
    navigator.pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Nova versão agendada para ${_dateFormat.format(_effectiveAt.toLocal())}.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: VeraProbColors.surface,
      title: Row(
        children: [
          RuleTypeIcon(ruleType: widget.ruleType, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Agendar: ${ruleTypeLabel(widget.ruleType)}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RuleParamField(
                label: _param.label,
                hint: _param.hint,
                controller: _controllers[_param.configKey]!,
                inputType: const TextInputType.numberWithOptions(
                  decimal: false,
                ),
                helpText: _param.help,
              ),
              const SizedBox(height: 16),
              _EffectiveDateRow(effectiveAt: _effectiveAt, onPick: _pickDate),
              const SizedBox(height: 16),
              RuleImpactSimulationPanel(
                ruleType: widget.ruleType,
                currentRule: widget.currentRule,
                controllers: _controllers,
                expanded: _impactExpanded,
                onToggle: () =>
                    setState(() => _impactExpanded = !_impactExpanded),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: VeraProbColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _isSaving ? null : _submit,
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.event_available_outlined, size: 16),
          label: const Text('Agendar'),
        ),
      ],
    );
  }
}

class _EffectiveDateRow extends StatelessWidget {
  final DateTime effectiveAt;
  final VoidCallback onPick;

  const _EffectiveDateRow({required this.effectiveAt, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.event_outlined,
            size: 16,
            color: VeraProbColors.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vigência a partir de',
                  style: TextStyle(
                    fontSize: 10,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
                Text(
                  _dateFormat.format(effectiveAt.toLocal()),
                  style: const TextStyle(
                    fontSize: 13,
                    color: VeraProbColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onPick, child: const Text('ALTERAR')),
        ],
      ),
    );
  }
}
