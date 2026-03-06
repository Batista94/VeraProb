import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:busflow/core/theme/app_theme.dart';
import 'package:busflow/domain/sla_audit/evaluation_trace.dart';
import 'package:busflow/domain/sla_audit/sla_ledger_entry.dart';
import 'package:busflow/state/providers/investigation_providers.dart';

final _timeFormat = DateFormat('HH:mm:ss');
final _dateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');

/// OCC Investigation Modal — Read-only forensic analysis of contractual
/// evaluation decisions. Displays the causal chain from ledger events
/// through rule evaluation to decision outcomes.
class InvestigationModal extends ConsumerWidget {
  final String setId;
  final String contractId;

  const InvestigationModal({
    super.key,
    required this.setId,
    required this.contractId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracesAsync = ref.watch(evaluationTracesProvider(setId));
    final ledgerAsync = ref.watch(ledgerEntriesProvider(setId));

    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: BusFlowColors.background,
        appBar: AppBar(
          backgroundColor: BusFlowColors.surface,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
          ),
          title: Row(
            children: [
              const Icon(Icons.search, size: 18, color: BusFlowColors.primary),
              const SizedBox(width: 8),
              const Text(
                'Investigação de Avaliação',
                style: BusFlowTypography.sectionTitle,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: BusFlowColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: BusFlowColors.border),
                ),
                child: Text(
                  'SOMENTE LEITURA',
                  style: BusFlowTypography.caption.copyWith(
                    color: BusFlowColors.warning,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Context Header ────────────────────────────
              _ContextHeader(setId: setId, contractId: contractId),
              const SizedBox(height: 24),

              // ── Main Content ──────────────────────────────
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Ledger Timeline
                    Expanded(
                      flex: 1,
                      child: _LedgerTimelinePanel(
                        ledgerAsync: ledgerAsync,
                        triggeringEventId: tracesAsync.whenOrNull(
                          data: (traces) => traces.isNotEmpty
                              ? traces.first.triggeringEventId
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 24),

                    // Right: Evaluation Trace
                    Expanded(
                      flex: 2,
                      child: _EvaluationTracePanel(tracesAsync: tracesAsync),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Context Header
// ═══════════════════════════════════════════════════════════════

class _ContextHeader extends StatelessWidget {
  final String setId;
  final String contractId;

  const _ContextHeader({required this.setId, required this.contractId});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BusFlowColors.border),
      ),
      child: Row(
        children: [
          _HeaderChip(label: 'SET', value: setId),
          const SizedBox(width: 24),
          _HeaderChip(label: 'CONTRATO', value: contractId),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: BusFlowTypography.caption.copyWith(letterSpacing: 1.2),
        ),
        const SizedBox(height: 4),
        Text(value, style: BusFlowTypography.bodyMedium),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Ledger Timeline Panel
// ═══════════════════════════════════════════════════════════════

class _LedgerTimelinePanel extends StatelessWidget {
  final AsyncValue<List<SlaLedgerEntry>> ledgerAsync;
  final String? triggeringEventId;

  const _LedgerTimelinePanel({
    required this.ledgerAsync,
    this.triggeringEventId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BusFlowColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: BusFlowColors.border)),
            ),
            child: Row(
              children: [
                const Icon(Icons.timeline, size: 16, color: BusFlowColors.info),
                const SizedBox(width: 8),
                const Text(
                  'Linha do Tempo',
                  style: BusFlowTypography.sectionTitle,
                ),
              ],
            ),
          ),

          // Timeline Content
          Expanded(
            child: ledgerAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: BusFlowColors.primary),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Erro ao carregar ledger: $err',
                  style: BusFlowTypography.bodySmall.copyWith(
                    color: BusFlowColors.error,
                  ),
                ),
              ),
              data: (entries) {
                if (entries.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhum evento no ledger',
                      style: BusFlowTypography.bodySmall,
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isTriggering =
                        triggeringEventId != null &&
                        entry.eventId == triggeringEventId;

                    return _TimelineEvent(
                      entry: entry,
                      isTriggering: isTriggering,
                      isLast: index == entries.length - 1,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  final SlaLedgerEntry entry;
  final bool isTriggering;
  final bool isLast;

  const _TimelineEvent({
    required this.entry,
    required this.isTriggering,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final dotColor = isTriggering
        ? BusFlowColors.primary
        : BusFlowColors.border;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline rail
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: isTriggering ? 14 : 10,
                  height: isTriggering ? 14 : 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                    border: isTriggering
                        ? Border.all(color: BusFlowColors.primary, width: 2)
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 1, color: BusFlowColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Event content
          Expanded(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isTriggering
                    ? BusFlowColors.primary.withValues(alpha: 0.08)
                    : BusFlowColors.surfaceElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isTriggering
                      ? BusFlowColors.primary.withValues(alpha: 0.3)
                      : BusFlowColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _timeFormat.format(entry.occurredAtUtc),
                        style: BusFlowTypography.caption.copyWith(
                          color: BusFlowColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (isTriggering)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: BusFlowColors.primary.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'GATILHO',
                            style: BusFlowTypography.caption.copyWith(
                              color: BusFlowColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 9,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.type,
                    style: BusFlowTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Evaluation Trace Panel
// ═══════════════════════════════════════════════════════════════

class _EvaluationTracePanel extends StatelessWidget {
  final AsyncValue<List<EvaluationTrace>> tracesAsync;

  const _EvaluationTracePanel({required this.tracesAsync});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: BusFlowColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BusFlowColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: BusFlowColors.border)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.gavel,
                  size: 16,
                  color: BusFlowColors.secondary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Rastreabilidade da Avaliação',
                  style: BusFlowTypography.sectionTitle,
                ),
              ],
            ),
          ),

          // Trace Content
          Expanded(
            child: tracesAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: BusFlowColors.primary),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Erro ao carregar traces: $err',
                  style: BusFlowTypography.bodySmall.copyWith(
                    color: BusFlowColors.error,
                  ),
                ),
              ),
              data: (traces) {
                if (traces.isEmpty) {
                  return _NoTraceState();
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: traces.length,
                  itemBuilder: (context, index) {
                    return _TraceCard(trace: traces[index]);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Graceful empty state when no evaluation trace is available.
class _NoTraceState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline, size: 48, color: BusFlowColors.textDisabled),
          const SizedBox(height: 16),
          const Text(
            'Nenhuma rastreabilidade disponível',
            style: BusFlowTypography.sectionTitle,
          ),
          const SizedBox(height: 8),
          Text(
            'Esta obrigação pode ter sido processada antes\n'
            'da ativação do sistema de rastreabilidade.',
            textAlign: TextAlign.center,
            style: BusFlowTypography.bodySmall.copyWith(
              color: BusFlowColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Trace Card
// ═══════════════════════════════════════════════════════════════

class _TraceCard extends StatelessWidget {
  final EvaluationTrace trace;

  const _TraceCard({required this.trace});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: BusFlowColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: BusFlowColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trace Metadata Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: BusFlowColors.border)),
            ),
            child: Row(
              children: [
                _MetaChip(
                  icon: Icons.memory,
                  label: trace.engineVersion,
                  color: BusFlowColors.secondary,
                ),
                const SizedBox(width: 12),
                _MetaChip(
                  icon: Icons.access_time,
                  label: _dateFormat.format(trace.evaluatedAtUtc),
                  color: BusFlowColors.textSecondary,
                ),
                const Spacer(),
                Text(
                  '${trace.decisions.length} regra(s)',
                  style: BusFlowTypography.caption,
                ),
              ],
            ),
          ),

          // Decisions
          ...trace.decisions.map(
            (decision) => _DecisionRow(decision: decision),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: BusFlowTypography.bodySmall.copyWith(color: color)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Decision Row
// ═══════════════════════════════════════════════════════════════

class _DecisionRow extends StatelessWidget {
  final EvaluationDecision decision;

  const _DecisionRow({required this.decision});

  @override
  Widget build(BuildContext context) {
    final isPenalty = decision.outcome.contains('PENALTY');
    final isPass =
        decision.outcome == 'PASS' || decision.outcome == 'BINDING_CONFIRMED';
    final outcomeColor = isPenalty
        ? BusFlowColors.error
        : isPass
        ? BusFlowColors.success
        : BusFlowColors.info;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: BusFlowColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Rule header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: BusFlowColors.info.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  'P${decision.rulePriority}',
                  style: BusFlowTypography.badge.copyWith(
                    color: BusFlowColors.info,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  decision.ruleType,
                  style: BusFlowTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: outcomeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  decision.outcome,
                  style: BusFlowTypography.badge.copyWith(color: outcomeColor),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Rule metadata
          Row(
            children: [
              Text(
                'Regra: ${decision.ruleId.substring(0, 8)}…',
                style: BusFlowTypography.caption,
              ),
              const SizedBox(width: 16),
              Text(
                'Versão: v${decision.ruleVersion}',
                style: BusFlowTypography.caption,
              ),
              if (decision.financialImpactCents != null) ...[
                const Spacer(),
                Text(
                  'Impacto: R\$ ${(decision.financialImpactCents! / 100).toStringAsFixed(2)}',
                  style: BusFlowTypography.bodySmall.copyWith(
                    color: BusFlowColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),

          // Evidence
          if (decision.evidence.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: BusFlowColors.background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'EVIDÊNCIA',
                    style: BusFlowTypography.caption.copyWith(
                      letterSpacing: 1.0,
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...decision.evidence.entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text(
                            '${e.key}: ',
                            style: BusFlowTypography.caption.copyWith(
                              color: BusFlowColors.textSecondary,
                            ),
                          ),
                          Text(
                            '${e.value}',
                            style: BusFlowTypography.bodySmall.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
