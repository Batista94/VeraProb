import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/sla_audit/rule_version_history_entry.dart';
import '../../../../application/sla_audit/update_contractual_rule_command.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/sla_audit/contractual_rule.dart';
import '../../../../state/providers/auth_providers.dart';
import '../../../../state/providers/rule_studio_providers.dart';

// ── Screen ───────────────────────────────────────────────────────────────────

/// Rule Configuration Studio for a single contract.
///
/// Displays all active rules with visual parameter editors (7.2).
/// Each rule card has an [Edit] button that opens [_RuleEditDialog] (7.3).
/// A collapsible history panel shows all past versions per rule type (7.4).
/// The edit dialog integrates Financial Impact Simulation before saving (7.6).
///
/// Access: TENANT_ADMIN only (gated by [UserPermission.canEditSlaRules]).
class RuleStudioScreen extends ConsumerWidget {
  const RuleStudioScreen({super.key, required this.contractId, required this.contractName});

  final String contractId;
  final String contractName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRulesAsync = ref.watch(activeRulesProvider(contractId));
    final historyAsync = ref.watch(ruleHistoryProvider(contractId));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(contractName: contractName),
            const SizedBox(height: 24),
            Expanded(
              child: activeRulesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(message: e.toString()),
                data: (activeRules) => _Body(
                  contractId: contractId,
                  activeRules: activeRules,
                  historyAsync: historyAsync,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.contractName});
  final String contractName;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.tune_rounded, size: 28, color: PactaFlowColors.primary),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rule Configuration Studio',
                style: PactaFlowTypography.sectionTitle),
            Text(contractName,
                style: PactaFlowTypography.bodyMedium
                    .copyWith(color: PactaFlowColors.textSecondary)),
          ],
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: PactaFlowColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: PactaFlowColors.primary.withValues(alpha: 0.3)),
          ),
          child: const Text('TENANT_ADMIN',
              style: TextStyle(fontSize: 11, color: PactaFlowColors.primary)),
        ),
      ],
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _Body extends ConsumerWidget {
  const _Body({
    required this.contractId,
    required this.activeRules,
    required this.historyAsync,
  });

  final String contractId;
  final Map<SlaRuleType, RuleVersionHistoryEntry> activeRules;
  final AsyncValue<List<RuleVersionHistoryEntry>> historyAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left: Active Rule Cards ──────────────────────────
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Regras Ativas',
                  style: PactaFlowTypography.bodyMedium.copyWith(
                      color: PactaFlowColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: SlaRuleType.values
                      .map((type) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RuleCard(
                              contractId: contractId,
                              ruleType: type,
                              activeRule: activeRules[type],
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // ── Right: Version History Panel ─────────────────────
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Histórico de Versões',
                  style: PactaFlowTypography.bodyMedium.copyWith(
                      color: PactaFlowColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Expanded(
                child: historyAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorState(message: e.toString()),
                  data: (history) => _VersionHistoryPanel(history: history),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Rule Card ─────────────────────────────────────────────────────────────────

class _RuleCard extends ConsumerWidget {
  const _RuleCard({
    required this.contractId,
    required this.ruleType,
    required this.activeRule,
  });

  final String contractId;
  final SlaRuleType ruleType;
  final RuleVersionHistoryEntry? activeRule;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentUserRoleProvider);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PactaFlowColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activeRule != null
              ? PactaFlowColors.border
              : PactaFlowColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RuleTypeIcon(ruleType: ruleType),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_ruleTypeLabel(ruleType),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: PactaFlowColors.textPrimary)),
                    if (activeRule != null)
                      Text('v${activeRule!.ruleVersion}',
                          style: const TextStyle(
                              fontSize: 11, color: PactaFlowColors.textSecondary)),
                  ],
                ),
              ),
              if (activeRule != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: PactaFlowColors.onTime.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Ativa',
                      style: TextStyle(
                          fontSize: 10,
                          color: PactaFlowColors.onTime,
                          fontWeight: FontWeight.w600)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: PactaFlowColors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Não configurada',
                      style: TextStyle(
                          fontSize: 10,
                          color: PactaFlowColors.warning,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          if (activeRule != null) ...[
            const SizedBox(height: 12),
            _ConfigPreview(entry: activeRule!, ruleType: ruleType),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: Text(activeRule != null ? 'Editar Regra' : 'Configurar Regra'),
              style: OutlinedButton.styleFrom(
                foregroundColor: PactaFlowColors.primary,
                side: const BorderSide(color: PactaFlowColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () => _showEditDialog(context, ref, role),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, dynamic callerRole) {
    showDialog(
      context: context,
      builder: (_) => _RuleEditDialog(
        contractId: contractId,
        ruleType: ruleType,
        currentRule: activeRule,
        callerRole: callerRole,
      ),
    );
  }
}

// ── Config Preview ────────────────────────────────────────────────────────────

class _ConfigPreview extends StatelessWidget {
  const _ConfigPreview({required this.entry, required this.ruleType});

  final RuleVersionHistoryEntry entry;
  final SlaRuleType ruleType;

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items
          .map((item) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: PactaFlowColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(item,
                    style: const TextStyle(
                        fontSize: 12, color: PactaFlowColors.textSecondary)),
              ))
          .toList(),
    );
  }

  List<String> _buildItems() {
    final c = entry.config;
    return switch (ruleType.value) {
      'MAX_TOLERANCE_DELAY' => [
          'Tolerância: ${c['threshold_minutes']} min',
        ],
      'MAX_EVIDENCE_GAP' => [
          'Lacuna máx: ${c['max_gap_seconds']} s',
        ],
      'MIN_GEOFENCE_COVERAGE' => [
          'Permanência mín: ${c['min_dwell_seconds']} s',
        ],
      'NO_SHOW_PENALTY' => [
          'Penalidade: R\$ ${(((c['penalty_amount_cents'] as int?) ?? 0) / 100).toStringAsFixed(2)}',
        ],
      _ => ['Configurado'],
    };
  }
}

// ── Rule Edit Dialog ──────────────────────────────────────────────────────────

class _RuleEditDialog extends ConsumerStatefulWidget {
  const _RuleEditDialog({
    required this.contractId,
    required this.ruleType,
    required this.currentRule,
    required this.callerRole,
  });

  final String contractId;
  final SlaRuleType ruleType;
  final RuleVersionHistoryEntry? currentRule;
  final dynamic callerRole;

  @override
  ConsumerState<_RuleEditDialog> createState() => _RuleEditDialogState();
}

class _RuleEditDialogState extends ConsumerState<_RuleEditDialog> {
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  bool _showImpact = false;

  @override
  void initState() {
    super.initState();
    _controllers = _buildControllers();
  }

  Map<String, TextEditingController> _buildControllers() {
    final c = widget.currentRule?.config ?? {};
    return switch (widget.ruleType.value) {
      'MAX_TOLERANCE_DELAY' => {
          'threshold_minutes': TextEditingController(
              text: (c['threshold_minutes'] ?? 5).toString()),
        },
      'MAX_EVIDENCE_GAP' => {
          'max_gap_seconds': TextEditingController(
              text: (c['max_gap_seconds'] ?? 300).toString()),
        },
      'MIN_GEOFENCE_COVERAGE' => {
          'min_dwell_seconds': TextEditingController(
              text: (c['min_dwell_seconds'] ?? 30).toString()),
        },
      'NO_SHOW_PENALTY' => {
          'penalty_amount_cents': TextEditingController(
              text: ((c['penalty_amount_cents'] as int? ?? 0) / 100)
                  .toStringAsFixed(2)),
        },
      _ => {},
    };
  }

  Map<String, dynamic> _buildConfig() {
    return switch (widget.ruleType.value) {
      'MAX_TOLERANCE_DELAY' => {
          'threshold_minutes':
              int.tryParse(_controllers['threshold_minutes']!.text) ?? 5,
        },
      'MAX_EVIDENCE_GAP' => {
          'max_gap_seconds':
              int.tryParse(_controllers['max_gap_seconds']!.text) ?? 300,
        },
      'MIN_GEOFENCE_COVERAGE' => {
          'min_dwell_seconds':
              int.tryParse(_controllers['min_dwell_seconds']!.text) ?? 30,
        },
      'NO_SHOW_PENALTY' => {
          'penalty_amount_cents': ((double.tryParse(
                      _controllers['penalty_amount_cents']!.text) ??
                  0.0) *
              100).round(),
        },
      _ => {},
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final handler = ref.read(updateContractualRuleHandlerProvider);
      await handler.handle(UpdateContractualRuleCommand(
        organizationId:  ref.read(currentOrganizationIdProvider) ?? '',
        contractId:      widget.contractId,
        oldRuleId:       widget.currentRule?.id,
        ruleType:        widget.ruleType,
        newConfig:       _buildConfig(),
        evaluationOrder: widget.currentRule?.evaluationOrder ??
            SlaRuleType.values.indexOf(widget.ruleType),
        callerRole:      widget.callerRole,
      ));

      // Invalidate providers so the screen refreshes
      ref.invalidate(activeRulesProvider(widget.contractId));
      ref.invalidate(ruleHistoryProvider(widget.contractId));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nova versão da regra salva com sucesso.'),
            backgroundColor: PactaFlowColors.onTime,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: PactaFlowColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: PactaFlowColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          _RuleTypeIcon(ruleType: widget.ruleType),
          const SizedBox(width: 10),
          Text(_ruleTypeLabel(widget.ruleType),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.currentRule != null)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: PactaFlowColors.info.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: PactaFlowColors.info.withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: PactaFlowColors.info),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Salvar cria uma nova versão. A versão atual (v${widget.currentRule!.ruleVersion}) '
                        'é preservada no histórico (INV-1).',
                        style: const TextStyle(
                            fontSize: 12, color: PactaFlowColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            // ── Parameter Fields ──────────────────────────────
            ..._buildFields(),
            const SizedBox(height: 16),
            // ── Financial Impact Simulation ───────────────────
            _ImpactSimulationPanel(
              ruleType: widget.ruleType,
              currentRule: widget.currentRule,
              controllers: _controllers,
              expanded: _showImpact,
              onToggle: () => setState(() => _showImpact = !_showImpact),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save_outlined, size: 16),
          label: const Text('Salvar Nova Versão'),
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  List<Widget> _buildFields() {
    return switch (widget.ruleType.value) {
      'MAX_TOLERANCE_DELAY' => [
          _ParamField(
            label: 'Tolerância de Atraso (minutos)',
            hint: 'Ex: 5',
            controller: _controllers['threshold_minutes']!,
            inputType: TextInputType.number,
            helpText: 'Minutos de atraso antes de iniciar o cômputo de penalidade.',
          ),
        ],
      'MAX_EVIDENCE_GAP' => [
          _ParamField(
            label: 'Lacuna Máxima de Evidência (segundos)',
            hint: 'Ex: 300',
            controller: _controllers['max_gap_seconds']!,
            inputType: TextInputType.number,
            helpText:
                'Intervalo máximo (s) entre pings de telemetria antes de invalidar a evidência.',
          ),
        ],
      'MIN_GEOFENCE_COVERAGE' => [
          _ParamField(
            label: 'Permanência Mínima no Geofence (segundos)',
            hint: 'Ex: 30',
            controller: _controllers['min_dwell_seconds']!,
            inputType: TextInputType.number,
            helpText:
                'Tempo mínimo (s) que o veículo deve permanecer no geofence para validar a viagem.',
          ),
        ],
      'NO_SHOW_PENALTY' => [
          _ParamField(
            label: 'Valor da Penalidade No-Show (R\$)',
            hint: 'Ex: 150.00',
            controller: _controllers['penalty_amount_cents']!,
            inputType:
                const TextInputType.numberWithOptions(decimal: true),
            helpText:
                'Valor financeiro aplicado quando o veículo não se apresenta (após threshold).',
          ),
        ],
      _ => [],
    };
  }
}

// ── Financial Impact Simulation Panel ─────────────────────────────────────────

class _ImpactSimulationPanel extends StatelessWidget {
  const _ImpactSimulationPanel({
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
        color: PactaFlowColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PactaFlowColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.insights_outlined,
                      size: 16, color: PactaFlowColors.secondary),
                  const SizedBox(width: 8),
                  const Text('Simulação de Impacto Financeiro',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PactaFlowColors.secondary)),
                  const Spacer(),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: PactaFlowColors.textSecondary,
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
        style: TextStyle(fontSize: 12, color: PactaFlowColors.textSecondary),
      );
    }

    final rows = _buildImpactRows();
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: PactaFlowColors.border, height: 1),
        const SizedBox(height: 10),
        const Text(
          'Alteração de Parâmetro',
          style: TextStyle(
              fontSize: 11,
              color: PactaFlowColors.textDisabled,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        ...rows,
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: PactaFlowColors.warning.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            children: [
              Icon(Icons.warning_amber_outlined,
                  size: 12, color: PactaFlowColors.warning),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Simulação qualitativa — impacto quantitativo disponível na Phase 7 (Audit Exports).',
                  style: TextStyle(
                      fontSize: 11, color: PactaFlowColors.textSecondary),
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
            impactWhenDecreased: 'Invalida mais evidências — pode aumentar no-shows',
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
            currentValue: ((c['penalty_amount_cents'] as num?)?.toDouble() ?? 0) / 100,
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
        ? PactaFlowColors.textDisabled
        : delta > 0
            ? PactaFlowColors.warning
            : PactaFlowColors.info;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 11, color: PactaFlowColors.textDisabled)),
                Row(
                  children: [
                    Text(current,
                        style: const TextStyle(
                            fontSize: 13,
                            color: PactaFlowColors.textSecondary,
                            decoration: TextDecoration.lineThrough)),
                    const Icon(Icons.arrow_right_alt,
                        size: 14, color: PactaFlowColors.textDisabled),
                    Text(proposed,
                        style: const TextStyle(
                            fontSize: 13,
                            color: PactaFlowColors.textPrimary,
                            fontWeight: FontWeight.w600)),
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

// ── Version History Panel ─────────────────────────────────────────────────────

class _VersionHistoryPanel extends StatelessWidget {
  const _VersionHistoryPanel({required this.history});

  final List<RuleVersionHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history_outlined,
                size: 48,
                color: PactaFlowColors.textDisabled.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'Nenhuma regra configurada ainda.',
              style: TextStyle(
                  fontSize: 13, color: PactaFlowColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // Group by rule type
    final grouped = <SlaRuleType, List<RuleVersionHistoryEntry>>{};
    for (final entry in history) {
      grouped.putIfAbsent(entry.ruleType, () => []).add(entry);
    }

    return ListView(
      children: grouped.entries.map((e) {
        return _HistoryGroup(ruleType: e.key, entries: e.value);
      }).toList(),
    );
  }
}

class _HistoryGroup extends StatefulWidget {
  const _HistoryGroup({required this.ruleType, required this.entries});

  final SlaRuleType ruleType;
  final List<RuleVersionHistoryEntry> entries;

  @override
  State<_HistoryGroup> createState() => _HistoryGroupState();
}

class _HistoryGroupState extends State<_HistoryGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: PactaFlowColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: PactaFlowColors.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  _RuleTypeIcon(ruleType: widget.ruleType, size: 16),
                  const SizedBox(width: 8),
                  Text(_ruleTypeLabel(widget.ruleType),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: PactaFlowColors.textPrimary)),
                  const SizedBox(width: 8),
                  Text('${widget.entries.length} versões',
                      style: const TextStyle(
                          fontSize: 11, color: PactaFlowColors.textSecondary)),
                  const Spacer(),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 14,
                    color: PactaFlowColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            ...widget.entries.map((entry) => _HistoryRow(entry: entry)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final RuleVersionHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: PactaFlowColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: entry.isActive
                  ? PactaFlowColors.onTime
                  : PactaFlowColors.textDisabled,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('v${entry.ruleVersion}',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: PactaFlowColors.textPrimary)),
                    const SizedBox(width: 6),
                    if (entry.isActive)
                      const Text('(ativa)',
                          style: TextStyle(
                              fontSize: 10,
                              color: PactaFlowColors.onTime)),
                  ],
                ),
                Text(
                  _formatDateRange(entry),
                  style: const TextStyle(
                      fontSize: 10, color: PactaFlowColors.textDisabled),
                ),
              ],
            ),
          ),
          Text(
            _configSummary(entry),
            style: const TextStyle(
                fontSize: 11, color: PactaFlowColors.textSecondary),
          ),
        ],
      ),
    );
  }

  String _formatDateRange(RuleVersionHistoryEntry entry) {
    final from = _fmtDate(entry.activeFromUtc);
    if (entry.isActive) return 'Desde $from';
    final to = _fmtDate(entry.activeToUtc!);
    return '$from → $to';
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _configSummary(RuleVersionHistoryEntry e) {
    final c = e.config;
    return switch (e.ruleType.value) {
      'MAX_TOLERANCE_DELAY'   => '${c['threshold_minutes']} min',
      'MAX_EVIDENCE_GAP'      => '${c['max_gap_seconds']} s',
      'MIN_GEOFENCE_COVERAGE' => '${c['min_dwell_seconds']} s',
      'NO_SHOW_PENALTY' =>
        'R\$ ${(((c['penalty_amount_cents'] as int?) ?? 0) / 100).toStringAsFixed(2)}',
      _                       => '',
    };
  }
}

// ── Shared Widgets ────────────────────────────────────────────────────────────

class _RuleTypeIcon extends StatelessWidget {
  const _RuleTypeIcon({required this.ruleType, this.size = 20});

  final SlaRuleType ruleType;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (ruleType.value) {
      'MAX_TOLERANCE_DELAY'   => (Icons.schedule_outlined, PactaFlowColors.warning),
      'MAX_EVIDENCE_GAP'      => (Icons.signal_cellular_connected_no_internet_0_bar, PactaFlowColors.info),
      'MIN_GEOFENCE_COVERAGE' => (Icons.location_on_outlined, PactaFlowColors.onTime),
      'NO_SHOW_PENALTY'       => (Icons.money_off_outlined, PactaFlowColors.error),
      _                       => (Icons.rule_outlined, PactaFlowColors.textSecondary),
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

class _ParamField extends StatelessWidget {
  const _ParamField({
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
        Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: PactaFlowColors.textPrimary)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: inputType,
          style: const TextStyle(color: PactaFlowColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: PactaFlowColors.textDisabled),
            filled: true,
            fillColor: PactaFlowColors.surfaceElevated,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PactaFlowColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PactaFlowColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: PactaFlowColors.primary),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 4),
        Text(helpText,
            style: const TextStyle(
                fontSize: 11, color: PactaFlowColors.textDisabled)),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Erro: $message',
        style: const TextStyle(color: PactaFlowColors.error),
      ),
    );
  }
}

// ── Shared helper ─────────────────────────────────────────────────────────────

String _ruleTypeLabel(SlaRuleType type) => switch (type.value) {
      'MAX_TOLERANCE_DELAY'   => 'Tolerância de Atraso',
      'MAX_EVIDENCE_GAP'      => 'Lacuna de Evidência',
      'MIN_GEOFENCE_COVERAGE' => 'Permanência Mínima no Geofence',
      'NO_SHOW_PENALTY'       => 'Penalidade No-Show',
      _                       => type.value,
    };
