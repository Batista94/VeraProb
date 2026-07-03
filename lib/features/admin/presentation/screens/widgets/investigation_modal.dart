import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/investigation_providers.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/investigation_map_panel.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/ledger_event_humanizer.dart';

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
    return Dialog(
      backgroundColor: VeraProbColors.background,
      shape: const RoundedRectangleBorder(borderRadius: VeraProbRadii.xlAll),
      child: Container(
        width: 1100,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Custom AppBar ─────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                color: VeraProbColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: VeraProbColors.border),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    size: 18,
                    color: VeraProbColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Análise Forense de Decisões',
                    style: VeraProbTypography.sectionTitle,
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: VeraProbColors.surfaceElevated,
                      borderRadius: VeraProbRadii.smAll,
                      border: Border.all(color: VeraProbColors.border),
                    ),
                    child: Text(
                      'MODO AUDITORIA',
                      style: VeraProbTypography.caption.copyWith(
                        color: VeraProbColors.warning,
                        letterSpacing: 1.0,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: VeraProbColors.textSecondary,
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Fixed Body (Internal Scrolling) ─────────────────────────
            Expanded(
              child: InvestigationDossierBody(
                setId: setId,
                contractId: contractId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reusable decision-reconstruction body: context chips, execution map +
/// operational ledger timeline, and the engine evaluation traces.
///
/// Extracted from [InvestigationModal] so the consolidated `ForensicDossierModal`
/// can host the same "Decisões" surface as a tab without the standalone dialog
/// chrome.
class InvestigationDossierBody extends ConsumerWidget {
  final String setId;
  final String contractId;
  final bool showTraces;

  const InvestigationDossierBody({
    super.key,
    required this.setId,
    required this.contractId,
    this.showTraces = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Evaluation traces are fetched, but we only use them to find the triggeringEventId.
    // The panel itself has been moved to Evidência tab to kill duplication.
    final tracesAsync = ref.watch(evaluationTracesProvider(setId));
    final ledgerAsync = ref.watch(ledgerEntriesProvider(setId));

    final mainContent = showTraces
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Map Panel & Ledger Timeline
              Expanded(
                flex: 1,
                child: Column(
                  children: [
                    Consumer(
                      builder: (context, ref, child) {
                        final stateAsync = ref.watch(
                          executionStateProvider(setId),
                        );
                        return switch (stateAsync) {
                          AsyncData(:final value) =>
                            value == null
                                ? const SizedBox()
                                : InvestigationMapPanel(execution: value),
                          AsyncLoading() => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          AsyncError() => const SizedBox(),
                        };
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: _LedgerTimelinePanel(
                        ledgerAsync: ledgerAsync,
                        triggeringEventId: switch (tracesAsync) {
                          AsyncData(:final value) =>
                            value.isNotEmpty
                                ? value.first.triggeringEventId
                                : null,
                          _ => null,
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),

              // Right: Evaluation Trace
              Expanded(
                flex: 2,
                child: _EvaluationTracePanel(tracesAsync: tracesAsync),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Ledger Timeline (Primary Forensic Spine)
              Expanded(
                flex: 2,
                child: _LedgerTimelinePanel(
                  ledgerAsync: ledgerAsync,
                  triggeringEventId: switch (tracesAsync) {
                    AsyncData(:final value) =>
                      value.isNotEmpty ? value.first.triggeringEventId : null,
                    _ => null,
                  },
                ),
              ),
              const SizedBox(width: 24),

              // Right: Map Panel (Secondary Context)
              Expanded(
                flex: 1,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Consumer(
                      builder: (context, ref, child) {
                        final stateAsync = ref.watch(
                          executionStateProvider(setId),
                        );
                        return switch (stateAsync) {
                          AsyncData(:final value) =>
                            value == null
                                ? const SizedBox()
                                : InvestigationMapPanel(execution: value),
                          AsyncLoading() => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          AsyncError() => const SizedBox(),
                        };
                      },
                    ),
                  ],
                ),
              ),
            ],
          );

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Context Header ────────────────────────────
          _ContextHeader(setId: setId, contractId: contractId),
          const SizedBox(height: 24),

          // ── Main Content ──────────────────────────────
          Expanded(child: mainContent),
        ],
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
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
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
          style: VeraProbTypography.caption.copyWith(letterSpacing: 1.2),
        ),
        const SizedBox(height: 4),
        Text(value, style: VeraProbTypography.bodyMedium),
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
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: VeraProbColors.border)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.timeline,
                  size: 16,
                  color: VeraProbColors.info,
                ),
                const SizedBox(width: 8),
                Text(
                  'Ledger Operacional',
                  style: VeraProbTypography.sectionTitle,
                ),
              ],
            ),
          ),

          // Timeline Content
          Expanded(
            child: switch (ledgerAsync) {
              AsyncData(:final value) => _buildLedgerList(value),
              AsyncLoading() => const Center(
                child: CircularProgressIndicator(color: VeraProbColors.primary),
              ),
              AsyncError() => Center(
                child: Text(
                  'Não foi possível carregar o histórico operacional.',
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: VeraProbColors.error,
                  ),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerList(List<SlaLedgerEntry> value) {
    if (value.isEmpty) {
      return Center(
        child: Text(
          'Nenhum evento no ledger',
          style: VeraProbTypography.bodySmall,
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: value.length,
      itemBuilder: (context, index) {
        final entry = value[index];
        final isTriggering =
            triggeringEventId != null && entry.eventId == triggeringEventId;

        return _TimelineEvent(
          entry: entry,
          isTriggering: isTriggering,
          isLast: index == value.length - 1,
        );
      },
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
        ? VeraProbColors.primary
        : VeraProbColors.border;

    // The auditor's justification lives under transition-specific payload keys
    // (reviewer_reason / rejection_reason / resolution_reason / notes / reason).
    final reasonText = resolveLedgerReasonText(entry.payload);

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
                        ? Border.all(color: VeraProbColors.primary, width: 2)
                        : null,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 1, color: VeraProbColors.border),
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
                    ? VeraProbColors.primary.withValues(alpha: 0.08)
                    : VeraProbColors.surfaceElevated,
                borderRadius: VeraProbRadii.mdAll,
                border: Border.all(
                  color: isTriggering
                      ? VeraProbColors.primary.withValues(alpha: 0.3)
                      : VeraProbColors.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _timeFormat.format(entry.occurredAtUtc),
                        style: VeraProbTypography.caption.copyWith(
                          color: VeraProbColors.textSecondary,
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
                            color: VeraProbColors.primary.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: VeraProbRadii.smAll,
                          ),
                          child: Text(
                            'AUDITADO',
                            style: VeraProbTypography.caption.copyWith(
                              color: VeraProbColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 9,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Human label primary — the dispatcher reads plain language.
                  Text(
                    humanizeLedgerEventType(entry.type),
                    style: VeraProbTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  // Raw enum kept as forensic subtitle (MODO AUDITORIA citability).
                  Text(
                    entry.type,
                    style: VeraProbTypography.caption.copyWith(
                      fontFamily: 'monospace',
                      color: VeraProbColors.textSecondary,
                    ),
                  ),
                  // Forensic payload (Identity and Reason)
                  if (entry.payload['actor_email'] != null ||
                      (entry.operatorId != 'SYSTEM' &&
                          entry.operatorId.isNotEmpty) ||
                      entry.payload['reason_code'] != null ||
                      reasonText != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: VeraProbColors.background,
                        borderRadius: VeraProbRadii.smAll,
                        border: Border.all(color: VeraProbColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (entry.payload['actor_email'] != null ||
                              (entry.operatorId != 'SYSTEM' &&
                                  entry.operatorId.isNotEmpty))
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 14,
                                  color: VeraProbColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    (entry.payload['actor_email'] as String?) ??
                                        entry.operatorId,
                                    style: VeraProbTypography.caption.copyWith(
                                      color: VeraProbColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if ((entry.payload['actor_email'] != null ||
                                  (entry.operatorId != 'SYSTEM' &&
                                      entry.operatorId.isNotEmpty)) &&
                              (entry.payload['reason_code'] != null ||
                                  reasonText != null))
                            const SizedBox(height: 8),
                          if (entry.payload['reason_code'] != null)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: reasonText != null ? 4.0 : 0,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Código de Fundamentação: ',
                                    style: VeraProbTypography.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: VeraProbColors.textPrimary,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      humanizeReasonCode(
                                        entry.payload['reason_code'] as String,
                                      ),
                                      style: VeraProbTypography.caption
                                          .copyWith(
                                            color: VeraProbColors.textSecondary,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (reasonText != null)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.format_quote,
                                  size: 14,
                                  color: VeraProbColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    reasonText,
                                    style: VeraProbTypography.caption.copyWith(
                                      color: VeraProbColors.textSecondary,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
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
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Panel Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: VeraProbColors.border)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.gavel,
                  size: 16,
                  color: VeraProbColors.secondary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Rastreabilidade Forense',
                  style: VeraProbTypography.sectionTitle,
                ),
              ],
            ),
          ),

          // Trace Content
          Expanded(
            child: switch (tracesAsync) {
              AsyncData(:final value) => _buildTraceList(value),
              AsyncLoading() => const Center(
                child: CircularProgressIndicator(color: VeraProbColors.primary),
              ),
              AsyncError() => Center(
                child: Text(
                  'Não foi possível carregar a rastreabilidade.',
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: VeraProbColors.error,
                  ),
                ),
              ),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTraceList(List<EvaluationTrace> value) {
    if (value.isEmpty) {
      return _NoTraceState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: value.length,
      itemBuilder: (context, index) {
        return _TraceCard(trace: value[index]);
      },
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
          const Icon(
            Icons.info_outline,
            size: 48,
            color: VeraProbColors.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma rastreabilidade disponível',
            style: VeraProbTypography.sectionTitle,
          ),
          const SizedBox(height: 8),
          Text(
            'Esta obrigação pode ter sido processada antes\n'
            'da ativação do sistema de rastreabilidade.',
            textAlign: TextAlign.center,
            style: VeraProbTypography.bodySmall.copyWith(
              color: VeraProbColors.textSecondary,
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
        color: VeraProbColors.surfaceElevated,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trace Metadata Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: VeraProbColors.border)),
            ),
            child: Row(
              children: [
                _MetaChip(
                  icon: Icons.memory,
                  label: trace.engineVersion,
                  color: VeraProbColors.secondary,
                ),
                const SizedBox(width: 12),
                _MetaChip(
                  icon: Icons.access_time,
                  label: _dateFormat.format(trace.evaluatedAtUtc),
                  color: VeraProbColors.textSecondary,
                ),
                const Spacer(),
                Text(
                  '${trace.decisions.length} regra(s)',
                  style: VeraProbTypography.caption,
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
        Text(label, style: VeraProbTypography.bodySmall.copyWith(color: color)),
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
        ? VeraProbColors.error
        : isPass
        ? VeraProbColors.success
        : VeraProbColors.info;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: VeraProbColors.border)),
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
                  color: VeraProbColors.info.withValues(alpha: 0.1),
                  borderRadius: VeraProbRadii.smAll,
                ),
                child: Text(
                  'P${decision.rulePriority}',
                  style: VeraProbTypography.badge.copyWith(
                    color: VeraProbColors.info,
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  decision.ruleType,
                  style: VeraProbTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: outcomeColor.withValues(alpha: 0.1),
                  borderRadius: VeraProbRadii.smAll,
                ),
                child: Text(
                  decision.outcome,
                  style: VeraProbTypography.badge.copyWith(color: outcomeColor),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Rule metadata
          Row(
            children: [
              Text(
                'Regra: ${decision.ruleId.length > 8 ? decision.ruleId.substring(0, 8) : decision.ruleId}…',
                style: VeraProbTypography.caption,
              ),
              const SizedBox(width: 16),
              Text(
                'Versão: v${decision.ruleVersion}',
                style: VeraProbTypography.caption,
              ),
              if (decision.financialImpactCents != null) ...[
                const Spacer(),
                Text(
                  'Impacto: R\$ ${(decision.financialImpactCents! / 100).toStringAsFixed(2)}',
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: VeraProbColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),

          // Evidence
          if (decision.evidence.toJson().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: VeraProbColors.background,
                borderRadius: VeraProbRadii.smAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PROVA DOCUMENTAL',
                    style: VeraProbTypography.caption.copyWith(
                      letterSpacing: 1.0,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...decision.evidence.toJson().entries.map(
                    (e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Text(
                            '${e.key}: ',
                            style: VeraProbTypography.caption.copyWith(
                              color: VeraProbColors.textSecondary,
                            ),
                          ),
                          Text(
                            '${e.value}',
                            style: VeraProbTypography.bodySmall.copyWith(
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
