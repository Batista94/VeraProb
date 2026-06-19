import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/investigation_providers.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/investigation_map_panel.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/ledger_event_humanizer.dart';

final _timeFormat = DateFormat('HH:mm:ss');

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                      borderRadius: BorderRadius.circular(4),
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

  const InvestigationDossierBody({
    super.key,
    required this.setId,
    required this.contractId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Evaluation traces are fetched, but we only use them to find the triggeringEventId.
    // The panel itself has been moved to Evidência tab to kill duplication.
    final tracesAsync = ref.watch(evaluationTracesProvider(setId));
    final ledgerAsync = ref.watch(ledgerEntriesProvider(setId));

    return Padding(
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
                            AsyncData(:final value) => () {
                              if (value == null) return const SizedBox();
                              return InvestigationMapPanel(execution: value);
                            }(),
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
            ),
          ),
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
        borderRadius: BorderRadius.circular(8),
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
        borderRadius: BorderRadius.circular(8),
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
              AsyncData(:final value) => () {
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
                        triggeringEventId != null &&
                        entry.eventId == triggeringEventId;

                    return _TimelineEvent(
                      entry: entry,
                      isTriggering: isTriggering,
                      isLast: index == value.length - 1,
                    );
                  },
                );
              }(),
              AsyncLoading() => const Center(
                child: CircularProgressIndicator(color: VeraProbColors.primary),
              ),
              AsyncError(:final error) => Center(
                child: Text(
                  'Erro ao carregar ledger: $error',
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
                borderRadius: BorderRadius.circular(6),
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
                            borderRadius: BorderRadius.circular(3),
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
                      entry.payload['reason'] != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: VeraProbColors.background,
                        borderRadius: BorderRadius.circular(4),
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
                                  entry.payload['reason'] != null))
                            const SizedBox(height: 8),
                          if (entry.payload['reason_code'] != null)
                            Padding(
                              padding: EdgeInsets.only(
                                bottom: entry.payload['reason'] != null
                                    ? 4.0
                                    : 0,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Motivo da Contestação: ',
                                    style: VeraProbTypography.caption.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: VeraProbColors.textPrimary,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      entry.payload['reason_code'] as String,
                                      style: VeraProbTypography.caption
                                          .copyWith(
                                            fontFamily: 'monospace',
                                            color: VeraProbColors.textSecondary,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (entry.payload['reason'] != null)
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
                                    entry.payload['reason'] as String,
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
