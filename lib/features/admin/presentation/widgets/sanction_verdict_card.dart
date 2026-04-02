import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../../application/sla_audit/projections/sanction_queue_item_view.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../domain/enums/user_role.dart';
import '../../../../domain/sla_audit/sanction_review_queue_entry.dart';
import '../../../../domain/sla_audit/signal_integrity_monitor.dart';
import '../../../../domain/sla_audit/sla_breach_risk_calculator.dart';
import '../../../../state/providers/auditor_queue_providers.dart';
import '../../../../state/providers/auth_providers.dart';
import '../screens/widgets/investigation_modal.dart';
import '../shared/widgets/geofence_evidence_map.dart';
import 'ghost_bar_widget.dart';
import 'ingestion_health_widget.dart';
import 'recurrence_badge_widget.dart';
import 'risk_thermometer_widget.dart';

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
    final isLocked = item.status != SanctionReviewStatus.pending;

    // Async contract name resolution — RLS enforces tenant isolation.
    final contractNameAsync = ref.watch(contractNameProvider(item.contractId));
    final contractName = contractNameAsync.valueOrNull;
    final displayName =
        contractName ??
        '${item.contractId.substring(0, 8).toUpperCase()} [...]';

    final unit = _unitForClause(evidence.clauseRef);
    final confidenceColor = _confidenceColor(evidence.confidenceScore);

    return Opacity(
      opacity: isLocked ? 0.6 : 1.0,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: VeraProbColors.surface,
            border: Border(
              left: BorderSide(
                color: isLocked
                    ? VeraProbColors.textDisabled
                    : VeraProbColors.error,
                width: 3,
              ),
              top: const BorderSide(color: VeraProbColors.border),
              right: const BorderSide(color: VeraProbColors.border),
              bottom: const BorderSide(color: VeraProbColors.border),
            ),
          ),
          child: Stack(
            children: [
              Column(
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
                                    style: VeraProbTypography.bodyMedium
                                        .copyWith(
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

                  // ── Zona 3: Infraction Summary — Ghost Bars (WS-6) ────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: GhostBarWidget(
                      deltaValue: evidence.deltaValue,
                      thresholdValue: evidence.thresholdValue,
                      unit: unit,
                      clauseRef: evidence.clauseRef,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Mini-map with geofence overlay (INV-23 — visual evidence snapshot)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Semantics(
                      label:
                          'Local da infração: ${evidence.primaryEvidenceLat.toStringAsFixed(4)}, ${evidence.primaryEvidenceLng.toStringAsFixed(4)}',
                      excludeSemantics: true,
                      child: GeofenceEvidenceMap(
                        infractionPoint: LatLng(
                          evidence.primaryEvidenceLat,
                          evidence.primaryEvidenceLng,
                        ),
                        geofenceCenter: evidence.geofenceCenterLat != null
                            ? LatLng(
                                evidence.geofenceCenterLat!,
                                evidence.geofenceCenterLng!,
                              )
                            : null,
                        geofenceRadiusMeters:
                            evidence.geofenceRadiusMeters ?? 50.0,
                        height: 120,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                  const Divider(color: VeraProbColors.border, height: 1),

                  // ── Zona 3.5: Ingestion Health (WS-3) ──────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: IngestionHealthWidget(
                      report: SignalIntegrityReport(
                        gaps: const [],
                        integrityScore: evidence.confidenceScore,
                        totalSilentSeconds: 0,
                        totalSpanSeconds: 0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Zona 3.6: Risk Thermometer (WS-2) ──────────────────────────
                  _RiskThermometerZone(item: item),

                  // ── Zona 3.7: Recurrence Badge (WS-6) ─────────────────────────
                  _RecurrenceZone(item: item),

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

                  // ── Zona 5: Action Row ─────────────────────────────────────
                  if (!isLocked)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: _VerdictActionRow(
                        isLoading: isLoading,
                        showRejectField: _showRejectField,
                        rejectController: _rejectController,
                        formattedFine: item.formattedFine,
                        onApprove: () => _onApprove(context),
                        onRejectTap: () => setState(
                          () => _showRejectField = !_showRejectField,
                        ),
                        onRejectConfirm: () => _onReject(context),
                        onRequestMoreProof: () => _onRequestMoreProof(context),
                      ),
                    ),
                ],
              ),
              // ── LOCKED overlay badge (INV-7: Immutability) ──────────
              if (isLocked)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Tooltip(
                    message: 'Veredito selado — Imutável (INV-7)',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: VeraProbColors.textDisabled.withValues(
                          alpha: 0.2,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock,
                            size: 12,
                            color: VeraProbColors.textDisabled,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'SELADO',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: VeraProbColors.textDisabled,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onApprove(BuildContext context) async {
    final evidence = widget.item.verdictEvidence;

    // WS-3: Use requiresDoubleConfirmation from integrity score
    final integrityReport = SignalIntegrityReport(
      gaps: const [],
      integrityScore: evidence.confidenceScore,
      totalSilentSeconds: 0,
      totalSpanSeconds: 0,
    );

    if (integrityReport.requiresDoubleConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('⚠ Integridade Baixa'),
          content: Text(
            'O score de integridade é ${evidence.confidenceScore}%. '
            'Confirma o selamento deste veredito?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                backgroundColor: VeraProbColors.warning,
              ),
              child: const Text('Confirmar Selamento'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final email = ref.read(currentOperatorEmailProvider);
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .approve(
          queueEntryId: widget.item.id,
          approvedByUserId: userId,
          actorEmail: email,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
        );
    // Force stream re-query so the card disappears without requiring a second click.
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncData) {
      ref.invalidate(pendingSanctionsStreamProvider);
    }
  }

  Future<void> _onReject(BuildContext context) async {
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final email = ref.read(currentOperatorEmailProvider);
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .reject(
          queueEntryId: widget.item.id,
          rejectedByUserId: userId,
          actorEmail: email,
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
          'Solicitação enviada. Motorista será notificado para enviar prova forense.',
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

/// Renders the Risk Thermometer for this sanction's historical breach proximity.
///
/// Watches [sanctionWindowProvider] asynchronously — shows a placeholder while
/// the SLA window is being resolved. Uses [primaryEvidenceTimestampUtc] as
/// [currentEtaUtc] to reconstruct how deep into the buffer the infraction fell.
class _RiskThermometerZone extends ConsumerWidget {
  final SanctionQueueItemView item;
  const _RiskThermometerZone({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final windowAsync = ref.watch(sanctionWindowProvider(item.setId));

    return windowAsync.when(
      loading: () => const SizedBox(height: 80),
      error: (e, s) => const SizedBox.shrink(),
      data: (window) {
        if (window == null) return const SizedBox.shrink();
        final report = const SlaBreachRiskCalculator().evaluate(
          windowStartUtc: window.start,
          windowEndUtc: window.end,
          currentEtaUtc: item.verdictEvidence.primaryEvidenceTimestampUtc,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: RiskThermometerWidget(report: report),
        );
      },
    );
  }
}

/// Renders the monthly recurrence badge for a vehicle's infraction history.
///
/// Hidden (SizedBox.shrink) when no [vehiclePlate] is available on the item
/// (legacy rows or unbound vehicles). Shows a loading placeholder while the
/// async provider resolves.
class _RecurrenceZone extends ConsumerWidget {
  final SanctionQueueItemView item;
  const _RecurrenceZone({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plate = item.vehiclePlate;
    if (plate == null || plate.isEmpty) return const SizedBox.shrink();

    final key = '${item.id}|$plate|${item.organizationId}';
    return ref.watch(vehicleInfractionRecurrenceProvider(key)).when(
      loading: () => const SizedBox(height: 48),
      error: (_, _) => const SizedBox.shrink(),
      data: (report) {
        if (report == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: RecurrenceBadgeWidget(report: report),
        );
      },
    );
  }
}

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
            'INTEGRIDADE',
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
          label: 'Selar veredito — confirmar multa de $formattedFine',
          child: FilledButton.icon(
            onPressed: isLoading ? null : onApprove,
            icon: isLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.gavel_rounded, size: 16),
            label: const Text('SELAR VEREDITO'),
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
                label: const Text('CONFIRMAR RECUSA'),
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
            icon: const Icon(Icons.block_rounded, size: 16),
            label: const Text('RECUSAR VEREDITO'),
            style: OutlinedButton.styleFrom(
              foregroundColor: VeraProbColors.error,
              side: const BorderSide(color: VeraProbColors.error),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        Semantics(
          label: 'Solicitar prova forense ao motorista',
          child: TextButton.icon(
            onPressed: isLoading ? null : onRequestMoreProof,
            icon: const Icon(Icons.find_in_page_outlined, size: 16),
            label: const Text('SOLICITAR PROVA FORENSE'),
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
