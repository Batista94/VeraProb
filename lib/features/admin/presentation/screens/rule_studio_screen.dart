import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/application/sla_audit/rule_version_history_entry.dart';
import 'package:veraprob/application/sla_audit/update_contractual_rule_command.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/rule_studio_providers.dart';
import 'package:veraprob/presentation/shared/widgets/veraprob_header.dart';
import 'package:veraprob/presentation/shared/widgets/veraprob_chip.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/rule_studio/rule_studio_shared.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/rule_studio/rule_studio_impact_panel.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/rule_studio/rule_studio_history_panel.dart';

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
  const RuleStudioScreen({
    super.key,
    required this.contractId,
    required this.contractName,
  });

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
            VeraProbHeader(
              icon: Icons.tune_rounded,
              title: 'Rule Configuration Studio',
              subtitle: contractName,
              actions: [
                const VeraProbChip(
                  label: 'TENANT_ADMIN',
                  color: VeraProbColors.primary,
                  outline: true,
                ),
              ],
            ),
            const SizedBox(height: VeraProbSpacing.lg),
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
              Text(
                'Regras Ativas',
                style: VeraProbTypography.bodyMedium.copyWith(
                  color: VeraProbColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: SlaRuleType.values
                      .map(
                        (type) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _RuleCard(
                            contractId: contractId,
                            ruleType: type,
                            activeRule: activeRules[type],
                          ),
                        ),
                      )
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
              Text(
                'Histórico de Versões',
                style: VeraProbTypography.bodyMedium.copyWith(
                  color: VeraProbColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: historyAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => _ErrorState(message: e.toString()),
                  data: (history) => RuleVersionHistoryPanel(history: history),
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
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: activeRule != null
              ? VeraProbColors.border
              : VeraProbColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RuleTypeIcon(ruleType: ruleType),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ruleTypeLabel(ruleType),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: VeraProbColors.textPrimary,
                      ),
                    ),
                    if (activeRule != null)
                      Text(
                        'v${activeRule!.ruleVersion}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: VeraProbColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (activeRule != null)
                const VeraProbChip(label: 'Ativa', color: VeraProbColors.onTime)
              else
                const VeraProbChip(
                  label: 'Não configurada',
                  color: VeraProbColors.warning,
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
              label: Text(
                activeRule != null ? 'Editar Regra' : 'Configurar Regra',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: VeraProbColors.primary,
                side: const BorderSide(color: VeraProbColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onPressed: () => _showEditDialog(context, ref, role),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    WidgetRef ref,
    dynamic callerRole,
  ) {
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
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: VeraProbColors.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                item,
                style: const TextStyle(
                  fontSize: 12,
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  List<String> _buildItems() {
    final c = entry.config;
    return switch (ruleType.value) {
      'MAX_TOLERANCE_DELAY' => ['Tolerância: ${c['threshold_minutes']} min'],
      'MAX_EVIDENCE_GAP' => ['Lacuna máx: ${c['max_gap_seconds']} s'],
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
          text: (c['threshold_minutes'] ?? 5).toString(),
        ),
      },
      'MAX_EVIDENCE_GAP' => {
        'max_gap_seconds': TextEditingController(
          text: (c['max_gap_seconds'] ?? 300).toString(),
        ),
      },
      'MIN_GEOFENCE_COVERAGE' => {
        'min_dwell_seconds': TextEditingController(
          text: (c['min_dwell_seconds'] ?? 30).toString(),
        ),
      },
      'NO_SHOW_PENALTY' => {
        'penalty_amount_cents': TextEditingController(
          text: ((c['penalty_amount_cents'] as int? ?? 0) / 100)
              .toStringAsFixed(2),
        ),
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
        'penalty_amount_cents':
            ((double.tryParse(_controllers['penalty_amount_cents']!.text) ??
                        0.0) *
                    100)
                .round(),
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
      await handler.handle(
        UpdateContractualRuleCommand(
          organizationId: ref.read(currentOrganizationIdProvider) ?? '',
          contractId: widget.contractId,
          oldRuleId: widget.currentRule?.id,
          ruleType: widget.ruleType,
          newConfig: _buildConfig(),
          evaluationOrder:
              widget.currentRule?.evaluationOrder ??
              SlaRuleType.values.indexOf(widget.ruleType),
          callerRole: widget.callerRole,
        ),
      );

      // Invalidate providers so the screen refreshes
      ref.invalidate(activeRulesProvider(widget.contractId));
      ref.invalidate(ruleHistoryProvider(widget.contractId));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nova versão da regra salva com sucesso.'),
            backgroundColor: VeraProbColors.onTime,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro: $e'),
            backgroundColor: VeraProbColors.error,
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
      backgroundColor: VeraProbColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          RuleTypeIcon(ruleType: widget.ruleType),
          const SizedBox(width: 10),
          Text(
            ruleTypeLabel(widget.ruleType),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.currentRule != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: VeraProbColors.info.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: VeraProbColors.info.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 14,
                        color: VeraProbColors.info,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Salvar cria uma nova versão. A versão atual (v${widget.currentRule!.ruleVersion}) '
                          'é preservada no histórico (INV-1).',
                          style: const TextStyle(
                            fontSize: 12,
                            color: VeraProbColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              // ── Parameter Fields ──────────────────────────────
              ..._buildFields(),
              const SizedBox(height: 16),
              // ── Financial Impact Simulation ───────────────────
              RuleImpactSimulationPanel(
                ruleType: widget.ruleType,
                currentRule: widget.currentRule,
                controllers: _controllers,
                expanded: _showImpact,
                onToggle: () => setState(() => _showImpact = !_showImpact),
              ),
            ],
          ),
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
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
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
        RuleParamField(
          label: 'Tolerância de Atraso (minutos)',
          hint: 'Ex: 5',
          controller: _controllers['threshold_minutes']!,
          inputType: TextInputType.number,
          helpText:
              'Minutos de atraso antes de iniciar o cômputo de penalidade.',
        ),
      ],
      'MAX_EVIDENCE_GAP' => [
        RuleParamField(
          label: 'Lacuna Máxima de Evidência (segundos)',
          hint: 'Ex: 300',
          controller: _controllers['max_gap_seconds']!,
          inputType: TextInputType.number,
          helpText:
              'Intervalo máximo (s) entre pings de telemetria antes de invalidar a evidência.',
        ),
      ],
      'MIN_GEOFENCE_COVERAGE' => [
        RuleParamField(
          label: 'Permanência Mínima no Geofence (segundos)',
          hint: 'Ex: 30',
          controller: _controllers['min_dwell_seconds']!,
          inputType: TextInputType.number,
          helpText:
              'Tempo mínimo (s) que o veículo deve permanecer no geofence para validar a viagem.',
        ),
      ],
      'NO_SHOW_PENALTY' => [
        RuleParamField(
          label: 'Valor da Penalidade No-Show (R\$)',
          hint: 'Ex: 150.00',
          controller: _controllers['penalty_amount_cents']!,
          inputType: const TextInputType.numberWithOptions(decimal: true),
          helpText:
              'Valor financeiro aplicado quando o veículo não se apresenta (após threshold).',
        ),
      ],
      _ => [],
    };
  }
}

// ── Error State ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Erro: $message',
        style: const TextStyle(color: VeraProbColors.error),
      ),
    );
  }
}
