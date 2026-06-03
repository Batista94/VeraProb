import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:veraprob/application/reporting/generate_forensic_dossier_handler.dart';
import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart'; // pr_scanner: ignore
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/investigation_modal.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/forensic_evidence_modal.dart';
import 'package:veraprob/features/admin/presentation/shared/compliance_widgets.dart';
import 'package:veraprob/features/admin/presentation/shared/widgets/reverse_geocoded_address.dart';
import 'package:veraprob/state/providers/reporting_providers.dart';
import 'package:veraprob/state/providers/sanction_focus_provider.dart';
import 'package:veraprob/state/providers/telegram_providers.dart';
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
  bool _isDossierLoading = false;
  String? _dossierError;

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

    // WS-5: Map-Sync selection state
    final focusedId = ref.watch(
      selectedSanctionFocusProvider.select((f) => f?.sanctionId),
    );
    final isFocused = focusedId == item.id;

    // Async contract name resolution — RLS enforces tenant isolation.
    final contractNameAsync = ref.watch(contractNameProvider(item.contractId));
    final contractName = contractNameAsync.value;
    final displayName =
        contractName ??
        '${item.contractId.substring(0, 8).toUpperCase()} [...]';

    final unit = _unitForClause(evidence.clauseRef);
    final confidenceColor = _confidenceColor(evidence.confidenceScore);

    // WS-5: Determine left border color based on focus/lock state
    final Color leftBorderColor;
    final double leftBorderWidth;
    if (isFocused) {
      leftBorderColor = VeraProbColors.primary;
      leftBorderWidth = 4;
    } else if (item.status == SanctionReviewStatus.disputed) {
      leftBorderColor = VeraProbColors.warning;
      leftBorderWidth = 3;
    } else if (isLocked) {
      leftBorderColor = VeraProbColors.textDisabled;
      leftBorderWidth = 3;
    } else {
      leftBorderColor = VeraProbColors.error;
      leftBorderWidth = 3;
    }

    return GestureDetector(
      onTap: () {
        // WS-5: Toggle map focus — unidirectional (List → Provider → Map)
        final current = ref.read(selectedSanctionFocusProvider);
        if (current?.sanctionId == item.id) {
          ref.read(selectedSanctionFocusProvider.notifier).set(null);
        } else {
          ref
              .read(selectedSanctionFocusProvider.notifier)
              .set(
                SanctionMapFocus(
                  sanctionId: item.id,
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
                  geofenceRadiusMeters: evidence.geofenceRadiusMeters ?? 50.0,
                ),
              );
        }
      },
      child: Opacity(
        opacity: item.status == SanctionReviewStatus.disputed
            ? 0.8
            : (isLocked ? 0.6 : 1.0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isFocused
                ? VeraProbColors.primary.withValues(alpha: 0.05)
                : VeraProbColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: VeraProbColors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // WS-5: Left accent line indicator (fixed Border + BorderRadius conflict in Flutter)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: leftBorderWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: leftBorderColor),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Zona 1: Identity Strip ─────────────────────────────────────
                  _buildIdentityStrip(item: item),

                  const SizedBox(height: 12),

                  // ── Zona 2: Financial Hero ─────────────────────────────────────
                  _buildFinancialHero(
                    item: item,
                    displayName: displayName,
                    confidenceColor: confidenceColor,
                  ),

                  const SizedBox(height: 16),
                  const Divider(color: VeraProbColors.border, height: 1),

                  // ── Zona 3: Infraction Summary — Ghost Bars (WS-6) / VEL Details ────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child:
                        evidence.clauseRef.split('-').first.toUpperCase() ==
                            'VEL'
                        ? _buildVelSpeedDetails(evidence, unit)
                        : GhostBarWidget(
                            deltaValue: evidence.deltaValue,
                            thresholdValue: evidence.thresholdValue,
                            unit: unit,
                            clauseRef: evidence.clauseRef,
                          ),
                  ),

                  const SizedBox(height: 12),

                  // WS-5: Mini-map removed — replaced by dedicated TelemetrySyncMap panel.
                  // Coordinates badge for quick reference (replaces visual footprint).
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Semantics(
                      label:
                          'Local da infração: ${evidence.primaryEvidenceLat.toStringAsFixed(4)}, ${evidence.primaryEvidenceLng.toStringAsFixed(4)}',
                      child: Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            size: 14,
                            color: isFocused
                                ? VeraProbColors.primary
                                : VeraProbColors.textDisabled,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${evidence.primaryEvidenceLat.toStringAsFixed(4)}, '
                            '${evidence.primaryEvidenceLng.toStringAsFixed(4)}',
                            style: VeraProbTypography.caption.copyWith(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              color: isFocused
                                  ? VeraProbColors.primary
                                  : VeraProbColors.textDisabled,
                            ),
                          ),
                          const Spacer(),
                          if (isFocused)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: VeraProbColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.map_outlined,
                                    size: 10,
                                    color: VeraProbColors.primary,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    'NO MAPA',
                                    style: VeraProbTypography.badge.copyWith(
                                      color: VeraProbColors.primary,
                                      fontSize: 8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Human-readable address for the infraction coordinates above.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: ReverseGeocodedAddress(
                      lat: evidence.primaryEvidenceLat,
                      lng: evidence.primaryEvidenceLng,
                    ),
                  ),

                  const SizedBox(height: 12),
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

                  // ── Zona 3.8: Evidence Compliance Badge ───────────────────────
                  _ComplianceBadgeZone(
                    setId: item.setId,
                    orgId: item.organizationId,
                  ),

                  const Divider(color: VeraProbColors.border, height: 1),

                  // ── Zona 4: Forensic Seal ──────────────────────────────────────
                  _ForensicSealRow(item: item),

                  // ── Zona 4.5: Dossier Download ─────────────────────────────────
                  _DossierDownloadRow(
                    isLoading: _isDossierLoading,
                    onDownload: () => _onDownloadDossier(),
                  ),

                  // ── Error feedback ─────────────────────────────────────────────
                  if (actionState is AsyncError || _dossierError != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: VeraProbColors.error.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          actionState is AsyncError
                              ? actionState.error.toString()
                              : _dossierError!,
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
                  if (isLocked && item.status == SanctionReviewStatus.applied)
                    _buildForensicEvidenceVisualizerRow(context, item),
                ],
              ),
              // ── LOCKED overlay badge (INV-7: Immutability) ──────────
              if (item.status == SanctionReviewStatus.disputed)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Tooltip(
                    message: 'Aguardando envio de prova forense',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: VeraProbColors.warning.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.hourglass_empty_outlined,
                            size: 12,
                            color: VeraProbColors.warning,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'AGUARDANDO EVIDÊNCIA',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: VeraProbColors.warning,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (isLocked)
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

  Widget _buildIdentityStrip({required SanctionQueueItemView item}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Row(
        children: [
          _ClauseBadge(clauseRef: item.verdictEvidence.clauseRef),
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
    );
  }

  Widget _buildFinancialHero({
    required SanctionQueueItemView item,
    required String displayName,
    required Color confidenceColor,
  }) {
    return Padding(
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
            score: item.verdictEvidence.confidenceScore,
            color: confidenceColor,
          ),
        ],
      ),
    );
  }

  Widget _buildForensicEvidenceVisualizerRow(
    BuildContext context,
    SanctionQueueItemView item,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    ForensicEvidenceModal(ledgerEntryId: item.ledgerEntryId),
              ),
              icon: const Icon(Icons.shield_outlined, size: 16),
              label: const Text('Visualizar Evidência Forense'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VeraProbColors.primary,
                side: const BorderSide(color: VeraProbColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
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
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .approve(
          queueEntryId: widget.item.id,
          approvedByUserId: userId,
          actorEmail: email,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
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
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .reject(
          queueEntryId: widget.item.id,
          rejectedByUserId: userId,
          actorEmail: email,
          rejectionReason: _rejectController.text,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
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

  Future<void> _onRequestMoreProof(BuildContext context) async {
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final email = ref.read(currentOperatorEmailProvider);
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .dispute(
          queueEntryId: widget.item.id,
          disputedByUserId: userId,
          actorEmail: email,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
        );
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncData) {
      ref.invalidate(pendingSanctionsStreamProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solicitação enviada. Motorista será notificado para enviar prova forense.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _onDownloadDossier() async {
    final item = widget.item;
    final evidence = item.verdictEvidence;
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final sessionId = ref.read(currentSessionIdProvider) ?? '';

    final entry = SlaLedgerEntry(
      eventId: item.ledgerEntryId,
      organizationId: item.organizationId,
      contractId: item.contractId,
      type: 'SANCTION_VERDICT',
      planVersion: 0,
      occurredAtUtc: item.createdAtUtc,
    );

    final command = GenerateForensicDossierCommand(
      sessionId: sessionId,
      operatorId: userId,
      jwtOrganizationId: item.organizationId,
      requestedOrganizationId: item.organizationId,
      ledgerEntry: entry,
      savingsCents: evidence.fineCents.cents,
      mapLat: evidence.primaryEvidenceLat,
      mapLng: evidence.primaryEvidenceLng,
    );

    setState(() {
      _isDossierLoading = true;
      _dossierError = null;
    });

    try {
      final handler = ref.read(generateForensicDossierHandlerProvider);
      final bytes = await handler.handle(command);
      final name =
          'dossie_forense_'
          '${item.ledgerEntryId.substring(0, 8)}_'
          '${DateTime.now().toUtc().millisecondsSinceEpoch}';
      await FileSaver.instance.saveFile(
        name: name,
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dossiê forense baixado com sucesso.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _dossierError = 'Falha ao gerar o dossiê. Tente novamente.',
      );
    } finally {
      if (mounted) setState(() => _isDossierLoading = false);
    }
  }

  Widget _buildVelSpeedDetails(VerdictEvidence evidence, String unit) {
    final recordedSpeed = evidence.thresholdValue + evidence.deltaValue;
    final limit = evidence.thresholdValue;
    final excess = evidence.deltaValue;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Row(
        children: [
          // 1. Velocidade Registrada (Dado de maior destaque)
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VELOCIDADE REGISTRADA',
                  style: VeraProbTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      recordedSpeed.toStringAsFixed(1),
                      style: VeraProbTypography.kpiValue.copyWith(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: VeraProbColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: VeraProbTypography.bodyMedium.copyWith(
                        color: VeraProbColors.textSecondary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Vertical divider
          Container(
            height: 40,
            width: 1,
            color: VeraProbColors.border,
            margin: const EdgeInsets.symmetric(horizontal: 8),
          ),
          // 2. Limite Contratual
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'LIMITE CONTRATUAL',
                  style: VeraProbTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    fontSize: 8.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${limit.toStringAsFixed(1)} $unit',
                  style: VeraProbTypography.dataValue.copyWith(
                    color: VeraProbColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          // 3. Excesso
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'EXCESSO',
                  style: VeraProbTypography.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    fontSize: 8.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '+${excess.toStringAsFixed(1)} $unit',
                  style: VeraProbTypography.dataValue.copyWith(
                    color: VeraProbColors.warning,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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

    return switch (windowAsync) {
      AsyncLoading() => const SizedBox(height: 80),
      AsyncError() => const SizedBox.shrink(),
      AsyncData(:final value) => () {
        if (value == null) return const SizedBox.shrink();
        final report = const SlaBreachRiskCalculator().evaluate(
          windowStartUtc: value.start,
          windowEndUtc: value.end,
          currentEtaUtc: item.verdictEvidence.primaryEvidenceTimestampUtc,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: RiskThermometerWidget(report: report),
        );
      }(),
    };
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
    return switch (ref.watch(vehicleInfractionRecurrenceProvider(key))) {
      AsyncLoading() => const SizedBox(height: 48),
      AsyncError() => const SizedBox.shrink(),
      AsyncData(:final value) => () {
        if (value == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: RecurrenceBadgeWidget(report: value),
        );
      }(),
    };
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

/// Zona 4.5: Dossier download row — always visible, even when verdict is locked.
/// INV-13: calls only application-layer provider, never infrastructure directly.
class _DossierDownloadRow extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onDownload;

  const _DossierDownloadRow({
    required this.isLoading,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Tooltip(
        message: 'Baixar Dossiê Forense Executive-Grade',
        child: OutlinedButton.icon(
          onPressed: isLoading ? null : onDownload,
          icon: isLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_outlined, size: 16),
          label: const Text('BAIXAR DOSSIÊ'),
          style: OutlinedButton.styleFrom(
            foregroundColor: VeraProbColors.primary,
            side: const BorderSide(color: VeraProbColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
        ),
      ),
    );
  }
}

/// Zona 3.8: Evidence compliance badge — reads from executionComplianceProvider.
/// keepAlive in the provider ensures no redundant RPCs on rebuild (INV-16).
class _ComplianceBadgeZone extends ConsumerWidget {
  final String setId;
  final String orgId;

  const _ComplianceBadgeZone({required this.setId, required this.orgId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final complianceAsync = ref.watch(
      executionComplianceProvider((organizationId: orgId, setId: setId)),
    );

    return switch (complianceAsync) {
      AsyncLoading() => const SizedBox.shrink(),
      AsyncError() => const SizedBox.shrink(),
      AsyncData(:final value) => () {
        if (value == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            children: [
              const Icon(
                Icons.assignment_turned_in_outlined,
                size: 13,
                color: VeraProbColors.textDisabled,
              ),
              const SizedBox(width: 6),
              const Text(
                'Evidências:',
                style: TextStyle(
                  fontSize: 11,
                  color: VeraProbColors.textDisabled,
                ),
              ),
              const SizedBox(width: 6),
              ComplianceBadge(compliance: value),
            ],
          ),
        );
      }(),
    };
  }
}
