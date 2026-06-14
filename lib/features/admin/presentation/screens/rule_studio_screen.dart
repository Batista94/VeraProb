import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/sla_audit/rule_version_history_entry.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/rule_studio_providers.dart';

import 'widgets/rule_studio/rule_studio_history_panel.dart';
import 'widgets/rule_studio/rule_studio_shared.dart';
import 'widgets/rule_studio/schedule_rule_dialog.dart';

final _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

/// Rule Studio — per-contract SLA rule lifecycle: view active rules, schedule
/// future versions, retire rules, and audit the full version history.
/// URL-addressable at `/admin/hub/contracts/:contractId/rules`.
class RuleStudioScreen extends ConsumerWidget {
  final String contractId;

  const RuleStudioScreen({super.key, required this.contractId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAsync = ref.watch(activeRulesProvider(contractId));
    final historyAsync = ref.watch(ruleHistoryProvider(contractId));

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(contractId: contractId),
          const SizedBox(height: 16),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final active = _buildActiveColumn(
                  context,
                  ref,
                  activeAsync,
                  historyAsync,
                );
                final history = _buildHistoryColumn(historyAsync);
                if (!wide) {
                  return ListView(
                    children: [
                      active,
                      const SizedBox(height: 24),
                      const Divider(color: VeraProbColors.border, height: 1),
                      const SizedBox(height: 16),
                      SizedBox(height: 360, child: history),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(child: active),
                    ),
                    const SizedBox(width: 20),
                    Expanded(flex: 2, child: history),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryColumn(
    AsyncValue<List<RuleVersionHistoryEntry>> historyAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Histórico de Versões',
          style: VeraProbTypography.sectionTitle.copyWith(fontSize: 15),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: switch (historyAsync) {
            AsyncLoading() => const Center(child: CircularProgressIndicator()),
            AsyncError() => const _RuleStudioMessage(
              'Não foi possível carregar o histórico de regras.',
            ),
            AsyncData(:final value) => RuleVersionHistoryPanel(history: value),
          },
        ),
      ],
    );
  }

  Widget _buildActiveColumn(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Map<SlaRuleType, RuleVersionHistoryEntry>> activeAsync,
    AsyncValue<List<RuleVersionHistoryEntry>> historyAsync,
  ) {
    return switch (activeAsync) {
      AsyncLoading() => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: CircularProgressIndicator(),
        ),
      ),
      AsyncError() => const _RuleStudioMessage(
        'Não foi possível carregar as regras ativas.',
      ),
      AsyncData(:final value) => () {
        if (value.isEmpty) {
          return const _RuleStudioMessage(
            'Nenhuma regra ativa configurada para este contrato.',
          );
        }
        final scheduledByType = _scheduledByType(historyAsync);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Regras Ativas',
              style: VeraProbTypography.sectionTitle.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 12),
            for (final entry in value.values)
              _RuleCard(
                contractId: contractId,
                rule: entry,
                scheduled: scheduledByType[entry.ruleType],
              ),
          ],
        );
      }(),
    };
  }

  Map<SlaRuleType, RuleVersionHistoryEntry> _scheduledByType(
    AsyncValue<List<RuleVersionHistoryEntry>> historyAsync,
  ) {
    final result = <SlaRuleType, RuleVersionHistoryEntry>{};
    final history = historyAsync.value;
    if (history == null) return result;
    for (final e in history) {
      if (e.isScheduled) result[e.ruleType] = e;
    }
    return result;
  }
}

class _Header extends StatelessWidget {
  final String contractId;
  const _Header({required this.contractId});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Voltar',
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/admin/hub/contracts'),
          icon: const Icon(Icons.arrow_back, color: VeraProbColors.textPrimary),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.tune_rounded, color: VeraProbColors.primary),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            'Estúdio de Regras SLA',
            style: VeraProbTypography.sectionTitle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _RuleStudioMessage extends StatelessWidget {
  final String text;
  const _RuleStudioMessage(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Text(
        text,
        style: const TextStyle(color: VeraProbColors.textSecondary),
      ),
    );
  }
}

/// One active rule with its current parameters, an optional scheduled-version
/// badge, and lifecycle actions (Agendar / Aposentar).
class _RuleCard extends ConsumerStatefulWidget {
  final String contractId;
  final RuleVersionHistoryEntry rule;
  final RuleVersionHistoryEntry? scheduled;

  const _RuleCard({
    required this.contractId,
    required this.rule,
    required this.scheduled,
  });

  @override
  ConsumerState<_RuleCard> createState() => _RuleCardState();
}

class _RuleCardState extends ConsumerState<_RuleCard> {
  bool _isRetiring = false;

  Future<void> _openSchedule() {
    return showDialog<void>(
      context: context,
      builder: (_) => ScheduleRuleDialog(
        contractId: widget.contractId,
        ruleType: widget.rule.ruleType,
        currentRule: widget.rule,
      ),
    );
  }

  Future<void> _retire() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VeraProbColors.surface,
        title: const Text('Aposentar regra'),
        content: Text(
          'Encerrar a versão ativa de "${ruleTypeLabel(widget.rule.ruleType)}"? '
          'O histórico é preservado (append-only).',
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => navigator.pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.error,
            ),
            child: const Text('Aposentar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isRetiring = true);
    final error = await retireContractualRule(ref, ruleId: widget.rule.id);
    if (!mounted) return;
    setState(() => _isRetiring = false);
    if (error != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(error), backgroundColor: VeraProbColors.error),
      );
      return;
    }
    ref.invalidate(ruleHistoryProvider(widget.contractId));
    ref.invalidate(activeRulesProvider(widget.contractId));
    messenger.showSnackBar(
      const SnackBar(content: Text('Regra aposentada. Histórico preservado.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rule = widget.rule;
    final scheduled = widget.scheduled;
    final canSchedule = ruleTypeSupportsScheduling(rule.ruleType);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              RuleTypeIcon(ruleType: rule.ruleType, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ruleTypeLabel(rule.ruleType),
                  overflow: TextOverflow.ellipsis,
                  style: VeraProbTypography.dataValue.copyWith(fontSize: 14),
                ),
              ),
              Text(
                'v${rule.ruleVersion}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _configSummary(rule),
            style: const TextStyle(
              fontSize: 13,
              color: VeraProbColors.textPrimary,
            ),
          ),
          if (scheduled != null) ...[
            const SizedBox(height: 10),
            _ScheduledBadge(scheduled: scheduled),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isRetiring ? null : _retire,
                  icon: _isRetiring
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.archive_outlined, size: 14),
                  label: const Text('Aposentar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: VeraProbColors.error,
                    side: BorderSide(
                      color: VeraProbColors.error.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Tooltip(
                  message: canSchedule
                      ? 'Agendar uma nova versão futura desta regra'
                      : 'Tipo de regra não suportado pelo agendador',
                  child: FilledButton.icon(
                    onPressed: canSchedule ? _openSchedule : null,
                    icon: const Icon(Icons.event_available_outlined, size: 14),
                    label: const Text('Agendar'),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _configSummary(RuleVersionHistoryEntry e) {
    final c = e.config;
    return switch (e.ruleType) {
      SlaRuleType.maxToleranceDelay =>
        'Tolerância: ${c['threshold_minutes']} min',
      SlaRuleType.maxEvidenceGap => 'Lacuna máx.: ${c['max_gap_seconds']} s',
      SlaRuleType.minGeofenceCoverage =>
        'Permanência mín.: ${c['min_dwell_seconds']} s',
      SlaRuleType.noShowPenalty =>
        'Penalidade: R\$ ${(((c['penalty_amount_cents'] as int?) ?? 0) / 100).toStringAsFixed(2)}',
      _ => 'Parâmetros configurados',
    };
  }
}

class _ScheduledBadge extends StatelessWidget {
  final RuleVersionHistoryEntry scheduled;
  const _ScheduledBadge({required this.scheduled});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: VeraProbColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: VeraProbColors.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.schedule_send_outlined,
            size: 13,
            color: VeraProbColors.warning,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Versão agendada (v${scheduled.ruleVersion}) — vigência '
              '${_dateFormat.format(scheduled.activeFromUtc.toLocal())}',
              overflow: TextOverflow.ellipsis,
              style: VeraProbTypography.caption.copyWith(
                color: VeraProbColors.warning,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
