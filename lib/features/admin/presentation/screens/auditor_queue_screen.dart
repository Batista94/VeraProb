import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/sla_audit/projections/sanction_queue_item_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/enums/user_role.dart';
import '../../../../state/providers/auditor_queue_providers.dart';

/// Auditor Queue Screen — Human-in-the-Loop review of engine-recommended sanctions.
///
/// Displays pending [SanctionQueueItemView] cards backed by Supabase Realtime.
/// Every card exposes VALIDAR / REJEITAR / DISPUTAR actions.
/// Satisfies INV-23: full VerdictEvidence provenance is shown per sanction.
class AuditorQueueScreen extends ConsumerWidget {
  const AuditorQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sanctionsAsync = ref.watch(pendingSanctionsStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(sanctionsAsync: sanctionsAsync),
          const SizedBox(height: 24),
          Expanded(
            child: sanctionsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Erro ao carregar fila: $e',
                  style: const TextStyle(color: VeraProbColors.error),
                ),
              ),
              data: (items) => items.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _SanctionCard(item: items[i]),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final AsyncValue<List<SanctionQueueItemView>> sanctionsAsync;
  const _Header({required this.sanctionsAsync});

  @override
  Widget build(BuildContext context) {
    final count = sanctionsAsync.maybeWhen(
      data: (items) => items.length,
      orElse: () => 0,
    );
    return Row(
      children: [
        const Icon(Icons.approval_outlined, color: VeraProbColors.primary),
        const SizedBox(width: 12),
        Text('Fila Auditora', style: VeraProbTypography.sectionTitle),
        const SizedBox(width: 12),
        if (count > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: VeraProbColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count pendente${count > 1 ? 's' : ''}',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.error,
              ),
            ),
          ),
      ],
    );
  }
}

// ── Empty State ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 56,
            color: VeraProbColors.textDisabled,
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma sanção pendente',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Todas as recomendações do engine foram revisadas.',
            style: TextStyle(color: VeraProbColors.textDisabled),
          ),
        ],
      ),
    );
  }
}

// ── Sanction Card ─────────────────────────────────────────────────────────────

class _SanctionCard extends ConsumerStatefulWidget {
  final SanctionQueueItemView item;
  const _SanctionCard({required this.item});

  @override
  ConsumerState<_SanctionCard> createState() => _SanctionCardState();
}

class _SanctionCardState extends ConsumerState<_SanctionCard> {
  bool _showRejectField = false;
  final _rejectController = TextEditingController();

  @override
  void dispose() {
    _rejectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(sanctionActionStateProvider(widget.item.id));
    final isLoading = actionState is AsyncLoading;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: VeraProbColors.border),
      ),
      color: VeraProbColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ───────────────────────────────────────────────
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: VeraProbColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'SANÇÃO RECOMENDADA',
                    style: VeraProbTypography.badge.copyWith(
                      color: VeraProbColors.error,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDate(widget.item.createdAtUtc),
                  style: const TextStyle(
                    fontSize: 11,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Contract / SET info ──────────────────────────────────────
            _InfoRow('Contrato', widget.item.contractId),
            _InfoRow('Veículo (SET)', widget.item.setId),
            _InfoRow('Cláusula', widget.item.verdictEvidence.clauseRef),
            const SizedBox(height: 8),
            _InfoRow(
              'Infração',
              '${widget.item.verdictEvidence.deltaValue.toStringAsFixed(1)} min',
            ),
            _InfoRow(
              'Limite',
              '${widget.item.verdictEvidence.thresholdValue.toStringAsFixed(1)} min',
            ),
            _InfoRow('Multa', widget.item.formattedFine),
            _InfoRow('Confiança', widget.item.formattedConfidence),

            // ── Provenance section ───────────────────────────────────────
            const SizedBox(height: 12),
            const _SectionLabel('Proveniência'),
            _InfoRow(
              'GPS',
              'lat ${widget.item.verdictEvidence.primaryEvidenceLat.toStringAsFixed(4)} · '
                  'lng ${widget.item.verdictEvidence.primaryEvidenceLng.toStringAsFixed(4)}',
            ),
            _InfoRow(
              'Timestamp',
              widget.item.verdictEvidence.primaryEvidenceTimestampUtc
                  .toIso8601String(),
            ),
            _InfoRow('Hash SHA-256', '${widget.item.shortEvidenceHash}...'),

            // ── Error feedback ───────────────────────────────────────────
            if (actionState is AsyncError) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: VeraProbColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  actionState.error.toString(),
                  style: const TextStyle(fontSize: 12, color: VeraProbColors.error),
                ),
              ),
            ],

            // ── Rejection reason field ───────────────────────────────────
            if (_showRejectField) ...[
              const SizedBox(height: 12),
              _RejectReasonField(controller: _rejectController),
            ],

            // ── Actions ──────────────────────────────────────────────────
            const SizedBox(height: 16),
            _ActionRow(
              isLoading: isLoading,
              showRejectField: _showRejectField,
              rejectController: _rejectController,
              onApprove: () => _onApprove(context),
              onRejectTap: () =>
                  setState(() => _showRejectField = !_showRejectField),
              onRejectConfirm: () => _onReject(context),
              onDispute: () => _onDispute(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onApprove(BuildContext context) async {
    // TODO(phase-9.3): replace with actual user/org from auth provider
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .approve(
          queueEntryId: widget.item.id,
          approvedByUserId: 'mock-auditor-id',
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
        );
  }

  Future<void> _onReject(BuildContext context) async {
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .reject(
          queueEntryId: widget.item.id,
          rejectedByUserId: 'mock-auditor-id',
          rejectionReason: _rejectController.text,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
        );
    if (mounted) {
      setState(() => _showRejectField = false);
      _rejectController.clear();
    }
  }

  Future<void> _onDispute(BuildContext context) async {
    // Dispute is initiated by the contractor — placeholder for Phase 9.4
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Disputa registrada. Contratante será notificado.'),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')} UTC';
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.8,
          color: VeraProbColors.textDisabled,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _RejectReasonField extends StatelessWidget {
  final TextEditingController controller;
  const _RejectReasonField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: 'Motivo da rejeição (mínimo 10 caracteres)',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final bool isLoading;
  final bool showRejectField;
  final TextEditingController rejectController;
  final VoidCallback onApprove;
  final VoidCallback onRejectTap;
  final VoidCallback onRejectConfirm;
  final VoidCallback onDispute;

  const _ActionRow({
    required this.isLoading,
    required this.showRejectField,
    required this.rejectController,
    required this.onApprove,
    required this.onRejectTap,
    required this.onRejectConfirm,
    required this.onDispute,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: isLoading ? null : onApprove,
          icon: isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 16),
          label: const Text('VALIDAR'),
          style: FilledButton.styleFrom(
            backgroundColor: VeraProbColors.primary,
          ),
        ),
        if (showRejectField)
          ListenableBuilder(
            listenable: rejectController,
            builder: (_, _) {
              final canConfirm = rejectController.text.trim().length >= 10;
              return FilledButton.icon(
                onPressed: isLoading || !canConfirm ? null : onRejectConfirm,
                icon: const Icon(Icons.block_rounded, size: 16),
                label: const Text('CONFIRMAR REJEIÇÃO'),
                style: FilledButton.styleFrom(
                  backgroundColor: VeraProbColors.error,
                ),
              );
            },
          )
        else
          OutlinedButton.icon(
            onPressed: isLoading ? null : onRejectTap,
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('REJEITAR'),
          ),
        TextButton.icon(
          onPressed: isLoading ? null : onDispute,
          icon: const Icon(Icons.gavel_outlined, size: 16),
          label: const Text('DISPUTAR'),
          style: TextButton.styleFrom(
            foregroundColor: VeraProbColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
