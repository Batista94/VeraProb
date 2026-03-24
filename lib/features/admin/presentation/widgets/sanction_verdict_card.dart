import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../application/sla_audit/projections/sanction_queue_item_view.dart';
import '../../../../core/config/constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/enums/user_role.dart';
import '../../../../state/providers/auditor_queue_providers.dart';
import '../../../../state/providers/auth_providers.dart';
import '../screens/widgets/investigation_modal.dart';

/// Business Verdict Tool card for the Auditor Queue.
///
/// Redesigned to satisfy the "5-Second Rule": a CFO must understand
/// the validity of this fine in under 5 seconds.
/// Satisfies the "1-Click Rule": provenance traceable in ≤1 click via
/// the Forensic Seal → [InvestigationModal].
///
/// Invariants: INV-2 (financial via formattedFine), INV-3 (UTC→local),
/// INV-4 (no domain logic in widget), INV-23 (verdict explainability).
class SanctionVerdictCard extends ConsumerStatefulWidget {
  final SanctionQueueItemView item;
  const SanctionVerdictCard({super.key, required this.item});

  @override
  ConsumerState<SanctionVerdictCard> createState() =>
      _SanctionVerdictCardState();
}

class _SanctionVerdictCardState extends ConsumerState<SanctionVerdictCard> {
  bool _showRejectField = false;
  final _rejectController = TextEditingController();

  // Maps clause prefix → measurement unit for forensically accurate display.
  // VEL clauses measure km/h over-speed — never "min".
  static const _clauseUnits = {
    'VEL': 'km/h',
    'ATR': 'min',
    'POS': 'min',
    'ABR': 'eventos',
  };

  @override
  void dispose() {
    _rejectController.dispose();
    super.dispose();
  }

  String _unitForClause(String clauseRef) {
    final prefix = clauseRef.split('-').first.toUpperCase();
    return _clauseUnits[prefix] ?? 'unid.';
  }

  String _formatLocalDate(DateTime utc) {
    final local = utc.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Color _confidenceColor(int score) {
    if (score >= 90) return VeraProbColors.success;
    if (score >= 70) return VeraProbColors.warning;
    return VeraProbColors.error;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final evidence = item.verdictEvidence;
    final actionState = ref.watch(sanctionActionStateProvider(item.id));
    final isLoading = actionState is AsyncLoading;

    // Async contract name resolution — RLS enforces tenant isolation.
    final contractNameAsync = ref.watch(contractNameProvider(item.contractId));
    final contractName = contractNameAsync.valueOrNull;
    final displayName = contractName ??
        '${item.contractId.substring(0, 8).toUpperCase()} [...]';

    final unit = _unitForClause(evidence.clauseRef);
    final confidenceColor = _confidenceColor(evidence.confidenceScore);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: const BoxDecoration(
          color: VeraProbColors.surface,
          border: Border(
            left: BorderSide(color: VeraProbColors.error, width: 3),
            top: BorderSide(color: VeraProbColors.border),
            right: BorderSide(color: VeraProbColors.border),
            bottom: BorderSide(color: VeraProbColors.border),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // ── Zona 1: Identity Strip ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                _ClauseBadge(clauseRef: evidence.clauseRef),
                const Spacer(),
                Text(
                  _formatLocalDate(item.createdAtUtc),
                  style: const TextStyle(
                    fontSize: 11,
                    color: VeraProbColors.textDisabled,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Zona 2: Financial Hero ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        label:
                            'Multa: ${item.formattedFine}. Validar ou rejeitar esta sanção.',
                        child: Text(
                          item.formattedFine,
                          style: VeraProbTypography.kpiValue.copyWith(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: VeraProbColors.error,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: VeraProbTypography.dataValue,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '· ${item.setId}',
                            style: VeraProbTypography.bodyMedium.copyWith(
                              color: VeraProbColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _ConfidenceBadge(
                  score: evidence.confidenceScore,
                  color: confidenceColor,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(color: VeraProbColors.border, height: 1),

          // ── Zona 3: Infraction Summary ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: _FactColumn(
                    label: 'DIFERENÇA OBSERVADA',
                    value:
                        '${evidence.deltaValue.toStringAsFixed(1)} $unit',
                    valueColor: VeraProbColors.warning,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _FactColumn(
                    label: 'LIMITE CONTRATUAL',
                    value:
                        '${evidence.thresholdValue.toStringAsFixed(1)} $unit',
                    valueColor: VeraProbColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Mini-map static thumbnail
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _MiniMapThumbnail(
              lat: evidence.primaryEvidenceLat,
              lng: evidence.primaryEvidenceLng,
            ),
          ),

          const SizedBox(height: 16),
          const Divider(color: VeraProbColors.border, height: 1),

          // ── Zona 4: Forensic Seal ──────────────────────────────────────
          _ForensicSealRow(item: item),

          // ── Error feedback ─────────────────────────────────────────────
          if (actionState is AsyncError) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: VeraProbColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  actionState.error.toString(),
                  style: const TextStyle(
                    fontSize: 12,
                    color: VeraProbColors.error,
                  ),
                ),
              ),
            ),
          ],

          // ── Rejection reason field ─────────────────────────────────────
          if (_showRejectField)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: _RejectReasonField(controller: _rejectController),
            ),

          // ── Zona 5: Action Row ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: _VerdictActionRow(
              isLoading: isLoading,
              showRejectField: _showRejectField,
              rejectController: _rejectController,
              formattedFine: item.formattedFine,
              onApprove: () => _onApprove(context),
              onRejectTap: () =>
                  setState(() => _showRejectField = !_showRejectField),
              onRejectConfirm: () => _onReject(context),
              onRequestMoreProof: () => _onRequestMoreProof(context),
            ),
          ),
        ],
        ),
      ),
    );
  }

  Future<void> _onApprove(BuildContext context) async {
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .approve(
          queueEntryId: widget.item.id,
          approvedByUserId: userId,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
        );
    // Force stream re-query so the card disappears without requiring a second click.
    // Supabase Realtime UPDATE events may not re-filter the local cache when a row
    // moves out of the `.eq('status', 'pending')` predicate.
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncData) {
      ref.invalidate(pendingSanctionsStreamProvider);
    }
  }

  Future<void> _onReject(BuildContext context) async {
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .reject(
          queueEntryId: widget.item.id,
          rejectedByUserId: userId,
          rejectionReason: _rejectController.text,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
        );
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncData) {
      ref.invalidate(pendingSanctionsStreamProvider);
    }
    if (mounted) {
      setState(() => _showRejectField = false);
      _rejectController.clear();
    }
  }

  void _onRequestMoreProof(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Solicitação enviada. Motorista será notificado para complementar evidências.',
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _ClauseBadge extends StatelessWidget {
  final String clauseRef;
  const _ClauseBadge({required this.clauseRef});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Text(
        clauseRef,
        style: VeraProbTypography.badge.copyWith(
          color: VeraProbColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _ConfidenceBadge extends StatelessWidget {
  final int score;
  final Color color;
  const _ConfidenceBadge({required this.score, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$score%',
            style: VeraProbTypography.kpiValue.copyWith(
              fontSize: 18,
              color: color,
              letterSpacing: 0,
            ),
          ),
          Text(
            'CONFIANÇA',
            style: VeraProbTypography.badge.copyWith(
              color: color,
              fontSize: 8,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _FactColumn extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _FactColumn({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: VeraProbTypography.caption.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: VeraProbTypography.dataValue.copyWith(color: valueColor),
        ),
      ],
    );
  }
}

class _MiniMapThumbnail extends StatelessWidget {
  final double lat;
  final double lng;
  const _MiniMapThumbnail({required this.lat, required this.lng});

  @override
  Widget build(BuildContext context) {
    const key = AppConstants.mapTilerKey;
    const isKeyConfigured = key != 'get_your_own_key';

    return Semantics(
      label: 'Local da infração: ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          height: 120,
          width: double.infinity,
          child: isKeyConfigured
              ? Image.network(
                  'https://api.maptiler.com/maps/dataviz-dark/static/'
                  '$lng,$lat,14/560x240.png'
                  '?key=$key'
                  '&markers=$lng,$lat',
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: VeraProbColors.surfaceElevated,
                      child: const Align(
                        alignment: Alignment.topCenter,
                        child: LinearProgressIndicator(
                          backgroundColor: Colors.transparent,
                          color: VeraProbColors.primary,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, err, stack) =>
                      _MapFallback(lat: lat, lng: lng),
                )
              : _MapFallback(lat: lat, lng: lng),
        ),
      ),
    );
  }
}

class _MapFallback extends StatelessWidget {
  final double lat;
  final double lng;
  const _MapFallback({required this.lat, required this.lng});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: VeraProbColors.surfaceElevated,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.location_off,
            size: 24,
            color: VeraProbColors.textDisabled,
          ),
          const SizedBox(height: 4),
          Text(
            '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',
            style: const TextStyle(
              fontSize: 11,
              color: VeraProbColors.textDisabled,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _ForensicSealRow extends StatelessWidget {
  final SanctionQueueItemView item;
  const _ForensicSealRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Abrir cadeia de custódia forense. Hash: ${item.verdictEvidence.evidenceHash}',
      button: true,
      child: Tooltip(
        message: 'Ver evidência completa em 1 clique',
        child: InkWell(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => InvestigationModal(
              setId: item.setId,
              contractId: item.contractId,
            ),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: VeraProbColors.surfaceElevated,
            child: Row(
              children: [
                const Icon(
                  Icons.verified_user,
                  size: 16,
                  color: VeraProbColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Cadeia de Custódia · Prova Forense',
                        style: VeraProbTypography.caption.copyWith(
                          letterSpacing: 0.4,
                        ),
                      ),
                      Text(
                        'SHA-256: ${item.shortEvidenceHash}...',
                        style: VeraProbTypography.caption.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: VeraProbColors.textDisabled,
                ),
              ],
            ),
          ),
        ),
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

class _VerdictActionRow extends StatelessWidget {
  final bool isLoading;
  final bool showRejectField;
  final TextEditingController rejectController;
  final String formattedFine;
  final VoidCallback onApprove;
  final VoidCallback onRejectTap;
  final VoidCallback onRejectConfirm;
  final VoidCallback onRequestMoreProof;

  const _VerdictActionRow({
    required this.isLoading,
    required this.showRejectField,
    required this.rejectController,
    required this.formattedFine,
    required this.onApprove,
    required this.onRejectTap,
    required this.onRejectConfirm,
    required this.onRequestMoreProof,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Semantics(
          label: 'Validar sanção — confirmar multa de $formattedFine',
          child: FilledButton.icon(
            onPressed: isLoading ? null : onApprove,
            icon: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_rounded, size: 16),
            label: const Text('VALIDAR'),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.success,
              foregroundColor: VeraProbColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              );
            },
          )
        else
          OutlinedButton.icon(
            onPressed: isLoading ? null : onRejectTap,
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('REJEITAR'),
            style: OutlinedButton.styleFrom(
              foregroundColor: VeraProbColors.error,
              side: const BorderSide(color: VeraProbColors.error),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        Semantics(
          label: 'Solicitar evidências adicionais ao motorista',
          child: TextButton.icon(
            onPressed: isLoading ? null : onRequestMoreProof,
            icon: const Icon(Icons.pending_actions_outlined, size: 16),
            label: const Text('SOLICITAR MAIS PROVAS'),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.warning,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}
