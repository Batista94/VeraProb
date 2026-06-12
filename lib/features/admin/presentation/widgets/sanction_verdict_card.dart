import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:veraprob/application/reporting/generate_forensic_dossier_handler.dart';
import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/application/sla_audit/resolve_dispute_command.dart'
    show DisputeResolution;
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
import 'dispute_reason_code_dropdown.dart';
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
  // Dispute resolution (disputed → *) — mutually exclusive reason fields.
  bool _showAcceptField = false;
  bool _showRefuseField = false;
  // Structured taxonomy code (Componente 4.2). Required for accept/overturn;
  // free-text becomes mandatory only when this equals 'OTHER'.
  String? _selectedReasonCode;
  final _acceptReasonController = TextEditingController();
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
    _acceptReasonController.dispose();
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
    // Pacote 3: `disputed` is now interactive (auditor resolves the dispute);
    // Phase 10.5: `pending_peer_review` is interactive (second auditor confirms/
    // declines). Only terminal verdicts (applied/rejected) are locked.
    final isLocked =
        item.status != SanctionReviewStatus.pending &&
        item.status != SanctionReviewStatus.disputed &&
        item.status != SanctionReviewStatus.pendingPeerReview;

    // Dual-control: the current auditor cannot confirm a verdict they requested.
    final currentUserId = ref.watch(currentOperatorIdProvider);
    final isOwnPeerRequest =
        item.status == SanctionReviewStatus.pendingPeerReview &&
        item.firstReviewerId != null &&
        item.firstReviewerId == currentUserId;

    // INV-14/INV-23: the bound asset (vehicle) is mandatory to seal the evidence.
    // An unidentified asset cannot anchor a forensic verdict.
    final canSeal = (item.vehiclePlate?.trim().isNotEmpty ?? false);

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

    // WS-5: Left accent ALWAYS reflects verdict severity (status) — never focus.
    // Focus is signalled by the outer border tint + background + "NO MAPA" badge,
    // so a pending verdict keeps its red severity cue even while selected.
    final Color leftBorderColor;
    const double leftBorderWidth = 3;
    if (item.status == SanctionReviewStatus.disputed) {
      leftBorderColor = VeraProbColors.warning;
    } else if (item.status == SanctionReviewStatus.pendingPeerReview) {
      leftBorderColor = VeraProbColors.primary;
    } else if (item.status == SanctionReviewStatus.rejected) {
      // Refused verdict: attenuated red — distinct from the live pending red.
      leftBorderColor = VeraProbColors.error.withValues(alpha: 0.5);
    } else if (isLocked) {
      leftBorderColor = VeraProbColors.textDisabled;
    } else {
      leftBorderColor = VeraProbColors.error;
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
        // disputed demands attention → full opacity; only sealed/refused dim.
        opacity: isLocked ? 0.6 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isFocused
                ? VeraProbColors.primary.withValues(alpha: 0.05)
                : VeraProbColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFocused ? VeraProbColors.primary : VeraProbColors.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
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
                      // Always re-frame the map to the forensic point — even when
                      // this sanction is already selected and the auditor panned
                      // away. recenter() emits a distinct event every tap.
                      onTap: () {
                        ref
                            .read(selectedSanctionFocusProvider.notifier)
                            .recenter(
                              SanctionMapFocus(
                                sanctionId: item.id,
                                infractionPoint: LatLng(
                                  evidence.primaryEvidenceLat,
                                  evidence.primaryEvidenceLng,
                                ),
                                geofenceCenter:
                                    evidence.geofenceCenterLat != null
                                    ? LatLng(
                                        evidence.geofenceCenterLat!,
                                        evidence.geofenceCenterLng!,
                                      )
                                    : null,
                                geofenceRadiusMeters:
                                    evidence.geofenceRadiusMeters ?? 50.0,
                              ),
                            );
                      },
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

                  // ── Zona 4.2: Refusal reason (rejected verdicts) ──────────────
                  if (item.status == SanctionReviewStatus.rejected &&
                      (item.rejectionReason?.trim().isNotEmpty ?? false))
                    _RefusalReasonZone(reason: item.rejectionReason!.trim()),

                  // ── Zona 4.3: Retraction provenance (re-pending verdicts) ─────
                  // A `pending` item carrying a non-null disputedAtUtc was
                  // disputed and later retracted — keep that trail visible
                  // (INV-23) so a cancelled contestation is never a silent ghost.
                  if (item.status == SanctionReviewStatus.pending &&
                      item.disputedAtUtc != null)
                    _RetractionProvenanceZone(item: item),

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

                  // ── Reason fields ──────────────────────────────────────────────
                  if (_showRejectField)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _RejectReasonField(controller: _rejectController),
                    ),
                  if (_showAcceptField || _showRefuseField)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                      child: _DisputeReasonInput(
                        isAccept: _showAcceptField,
                        selectedCode: _selectedReasonCode,
                        onCodeChanged: (code) =>
                            setState(() => _selectedReasonCode = code),
                        freeTextController: _showAcceptField
                            ? _acceptReasonController
                            : _rejectController,
                      ),
                    ),

                  // ── Zona 5: Action Row ─────────────────────────────────────
                  if (item.status == SanctionReviewStatus.pending)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: _VerdictActionRow(
                        isLoading: isLoading,
                        canSeal: canSeal,
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
                    )
                  else if (item.status == SanctionReviewStatus.disputed)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item.resolutionDueAtUtc != null) ...[
                            _DisputeSlaChip(dueAtUtc: item.resolutionDueAtUtc!),
                            const SizedBox(height: 12),
                          ],
                          _DisputeResolutionRow(
                            isLoading: isLoading,
                            showAcceptField: _showAcceptField,
                            showRefuseField: _showRefuseField,
                            selectedReasonCode: _selectedReasonCode,
                            acceptController: _acceptReasonController,
                            refuseController: _rejectController,
                            onAcceptTap: () => setState(() {
                              _showAcceptField = !_showAcceptField;
                              _showRefuseField = false;
                            }),
                            onAcceptConfirm: _onAcceptDispute,
                            onRefuseTap: () => setState(() {
                              _showRefuseField = !_showRefuseField;
                              _showAcceptField = false;
                            }),
                            onRefuseConfirm: _onRefuseDispute,
                            onRetract: _onRetractDispute,
                          ),
                        ],
                      ),
                    )
                  else if (item.status ==
                      SanctionReviewStatus.pendingPeerReview)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                      child: _PeerReviewRow(
                        isLoading: isLoading,
                        isOwnRequest: isOwnPeerRequest,
                        proposedAction: item.peerReviewProposedAction,
                        onConfirm: () => _onConfirmPeerReview(context),
                        onDecline: () => _onDeclinePeerReview(context),
                      ),
                    ),
                  if (item.status == SanctionReviewStatus.applied)
                    _buildForensicEvidenceVisualizerRow(context, item),
                ],
              ),
              // WS-5: Severity accent — painted AFTER content so full-bleed rows
              // (e.g. the forensic seal) never cover it; clipped to card radius.
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: leftBorderWidth,
                child: DecoratedBox(
                  key: const ValueKey('verdict-severity-accent'),
                  decoration: BoxDecoration(color: leftBorderColor),
                ),
              ),
              // ── LOCKED overlay badge (INV-7: Immutability) ──────────
              if (item.status == SanctionReviewStatus.disputed)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Tooltip(
                    message: 'Evidência submetida. Resolva abaixo.',
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
              else if (item.status == SanctionReviewStatus.pendingPeerReview)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Tooltip(
                    message:
                        'Veredito de alto valor — requer um segundo auditor',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: VeraProbColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: VeraProbColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.groups_2_outlined,
                            size: 12,
                            color: VeraProbColors.primary,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'AGUARDANDO 2º AUDITOR',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: VeraProbColors.primary,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (item.status == SanctionReviewStatus.rejected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Tooltip(
                    message: 'Sanção recusada — multa não aplicada',
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: VeraProbColors.error.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: VeraProbColors.error.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.block_rounded,
                            size: 12,
                            color: VeraProbColors.error,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'VEREDITO RECUSADO',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: VeraProbColors.error,
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
          const SizedBox(width: 8),
          Flexible(
            child: _AssetOperatorStrip(
              assetIdentifier: item.assetIdentifier,
              operatorName: item.operatorName,
            ),
          ),
          const SizedBox(width: 8),
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

  Future<void> _onAcceptDispute() => _resolveDispute(
    DisputeResolution.accept,
    _acceptReasonController.text,
    _selectedReasonCode,
  );

  Future<void> _onRefuseDispute() => _resolveDispute(
    DisputeResolution.overturn,
    _rejectController.text,
    _selectedReasonCode,
  );

  Future<void> _onRetractDispute() =>
      _resolveDispute(DisputeResolution.retract, null, null);

  Future<void> _resolveDispute(
    DisputeResolution resolution,
    String? reason,
    String? reasonCode,
  ) async {
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final email = ref.read(currentOperatorEmailProvider);
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    final trimmed = reason?.trim();
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .resolveDispute(
          queueEntryId: widget.item.id,
          resolution: resolution,
          resolvedByUserId: userId,
          actorEmail: email,
          resolutionReason: (trimmed == null || trimmed.isEmpty)
              ? null
              : trimmed,
          reasonCode: reasonCode,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
        );
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncData) {
      // Card leaves the disputed list regardless of the chosen arc.
      ref.invalidate(disputedSanctionsStreamProvider);
      // retract returns it to the pending queue.
      if (resolution == DisputeResolution.retract) {
        ref.invalidate(pendingSanctionsStreamProvider);
      }
    }
    if (mounted) {
      setState(() {
        _showAcceptField = false;
        _showRefuseField = false;
        _selectedReasonCode = null;
      });
      _acceptReasonController.clear();
      _rejectController.clear();
    }
  }

  Future<void> _onConfirmPeerReview(BuildContext context) async {
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final email = ref.read(currentOperatorEmailProvider);
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .confirmPeerReview(
          queueEntryId: widget.item.id,
          confirmedByUserId: userId,
          actorEmail: email,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
        );
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncData) {
      ref.invalidate(peerReviewSanctionsStreamProvider);
    }
  }

  Future<void> _onDeclinePeerReview(BuildContext context) async {
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final email = ref.read(currentOperatorEmailProvider);
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .declinePeerReview(
          queueEntryId: widget.item.id,
          declinedByUserId: userId,
          actorEmail: email,
          reason: '',
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
        );
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncData) {
      // Reverts to its origin lane (pending or disputed).
      ref.invalidate(peerReviewSanctionsStreamProvider);
      ref.invalidate(pendingSanctionsStreamProvider);
      ref.invalidate(disputedSanctionsStreamProvider);
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

/// Identity strip segment: bound Asset (vehicle plate) + Operator (driver name).
///
/// The auditor must know WHICH vehicle and WHO produced the evidence before
/// sealing or contesting (INV-14, INV-23). The asset identifier carries the
/// same visual weight as the clause badge; a missing plate is flagged in the
/// error color because it blocks sealing. A missing operator degrades
/// gracefully to "Não Identificado" — telemetry can arrive without an
/// authenticated driver.
class _AssetOperatorStrip extends StatelessWidget {
  final String? assetIdentifier;
  final String? operatorName;
  const _AssetOperatorStrip({
    required this.assetIdentifier,
    required this.operatorName,
  });

  @override
  Widget build(BuildContext context) {
    final hasAsset = (assetIdentifier?.trim().isNotEmpty ?? false);
    final hasOperator = (operatorName?.trim().isNotEmpty ?? false);
    final assetLabel = hasAsset ? assetIdentifier!.trim() : 'Sem veículo';
    final operatorLabel = hasOperator
        ? operatorName!.trim()
        : 'Não Identificado';

    return Semantics(
      label: 'Veículo: $assetLabel. Motorista: $operatorLabel.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 14,
            color: hasAsset ? VeraProbColors.textPrimary : VeraProbColors.error,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              assetLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VeraProbTypography.dataValue.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: hasAsset
                    ? VeraProbColors.textPrimary
                    : VeraProbColors.error,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const Text(
            '·',
            style: TextStyle(color: VeraProbColors.textDisabled, fontSize: 13),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.person_outline,
            size: 14,
            color: VeraProbColors.textSecondary,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              operatorLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: VeraProbTypography.bodyMedium.copyWith(
                fontSize: 12,
                fontStyle: hasOperator ? FontStyle.normal : FontStyle.italic,
                color: hasOperator
                    ? VeraProbColors.textSecondary
                    : VeraProbColors.textDisabled,
              ),
            ),
          ),
        ],
      ),
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
          borderRadius: BorderRadius.circular(8),
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: VeraProbColors.border, width: 0.5),
            ),
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
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
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

/// Zona 4.2: Refusal reason banner for `rejected` verdicts.
///
/// Surfaces the auditor's rationale (from `rejection_reason`) on the Concluídos
/// tab so a refused fine is never a silent ghost — INV-23 explainability.
class _RefusalReasonZone extends StatelessWidget {
  final String reason;
  const _RefusalReasonZone({required this.reason});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: VeraProbColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: VeraProbColors.error.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.block_rounded,
                  size: 13,
                  color: VeraProbColors.error,
                ),
                const SizedBox(width: 6),
                Text(
                  'MOTIVO DA RECUSA',
                  style: VeraProbTypography.badge.copyWith(
                    color: VeraProbColors.error,
                    fontSize: 9,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              reason,
              style: VeraProbTypography.bodyMedium.copyWith(
                fontSize: 12,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RejectReasonField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  const _RejectReasonField({
    required this.controller,
    this.labelText = 'Motivo da rejeição (mínimo 10 caracteres)',
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: labelText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}

class _VerdictActionRow extends StatelessWidget {
  final bool isLoading;
  final bool canSeal;
  final bool showRejectField;
  final TextEditingController rejectController;
  final String formattedFine;
  final VoidCallback onApprove;
  final VoidCallback onRejectTap;
  final VoidCallback onRejectConfirm;
  final VoidCallback onRequestMoreProof;

  const _VerdictActionRow({
    required this.isLoading,
    required this.canSeal,
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
    final sealBlockedReason = canSeal
        ? 'Selar veredito — confirmar multa de $formattedFine'
        : 'Veículo não identificado — não é possível selar a evidência';
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        Semantics(
          label: sealBlockedReason,
          child: Tooltip(
            message: sealBlockedReason,
            child: FilledButton.icon(
              onPressed: (isLoading || !canSeal) ? null : onApprove,
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
                disabledBackgroundColor: VeraProbColors.textDisabled.withValues(
                  alpha: 0.3,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
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

/// Zona 5 (disputed): inline Human Verdict Affirmation controls for a contested
/// verdict (Componente 5.4).
///
/// Mirrors [_VerdictActionRow] but closes the dispute loop (INV-23) with a
/// differentiated human signature — never a rubber-stamp:
/// - AFIRMAR VIOLAÇÃO → `disputed → applied` (fine upheld; seals the evidence
///   hash inline, INV-21), structured reason code (free-text only for `OTHER`).
/// - INIBIR VIOLAÇÃO → `disputed → rejected` (fine forgiven), structured reason
///   code AND a mandatory written comment (≥10) — forgiving a computed penalty
///   must carry human prose on record.
/// - CANCELAR SOLICITAÇÃO → `disputed → pending` (retract), no reason.
///
/// Inline (not modal) to avoid `barrierDismissible:false` stacking (Lesson 4)
/// and preserve map focus.
class _DisputeResolutionRow extends StatelessWidget {
  final bool isLoading;
  final bool showAcceptField;
  final bool showRefuseField;
  final String? selectedReasonCode;
  final TextEditingController acceptController;
  final TextEditingController refuseController;
  final VoidCallback onAcceptTap;
  final VoidCallback onAcceptConfirm;
  final VoidCallback onRefuseTap;
  final VoidCallback onRefuseConfirm;
  final VoidCallback onRetract;

  const _DisputeResolutionRow({
    required this.isLoading,
    required this.showAcceptField,
    required this.showRefuseField,
    required this.selectedReasonCode,
    required this.acceptController,
    required this.refuseController,
    required this.onAcceptTap,
    required this.onAcceptConfirm,
    required this.onRefuseTap,
    required this.onRefuseConfirm,
    required this.onRetract,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // INIBIR VIOLAÇÃO — forgives the fine; demands a written comment (5.4).
        if (showAcceptField)
          ListenableBuilder(
            listenable: acceptController,
            builder: (_, _) {
              final canConfirm = _inhibitionReasonSatisfied(
                selectedReasonCode,
                acceptController,
              );
              return FilledButton.icon(
                onPressed: isLoading || !canConfirm ? null : onAcceptConfirm,
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('CONFIRMAR INIBIÇÃO'),
                style: FilledButton.styleFrom(
                  backgroundColor: VeraProbColors.success,
                  foregroundColor: VeraProbColors.background,
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
            onPressed: isLoading ? null : onAcceptTap,
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('INIBIR VIOLAÇÃO'),
            style: OutlinedButton.styleFrom(
              foregroundColor: VeraProbColors.success,
              side: const BorderSide(color: VeraProbColors.success),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        // AFIRMAR VIOLAÇÃO — upholds the fine; seals the evidence hash (5.4).
        if (showRefuseField)
          ListenableBuilder(
            listenable: refuseController,
            builder: (_, _) {
              final canConfirm = _disputeReasonSatisfied(
                selectedReasonCode,
                refuseController,
              );
              return Tooltip(
                message:
                    'Afirmar sela o hash da evidência (INV-21) — veredito imutável',
                child: FilledButton.icon(
                  onPressed: isLoading || !canConfirm ? null : onRefuseConfirm,
                  icon: const Icon(Icons.gavel_rounded, size: 16),
                  label: const Text('CONFIRMAR AFIRMAÇÃO'),
                  style: FilledButton.styleFrom(
                    backgroundColor: VeraProbColors.error,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              );
            },
          )
        else
          OutlinedButton.icon(
            onPressed: isLoading ? null : onRefuseTap,
            icon: const Icon(Icons.gavel_rounded, size: 16),
            label: const Text('AFIRMAR VIOLAÇÃO'),
            style: OutlinedButton.styleFrom(
              foregroundColor: VeraProbColors.error,
              side: const BorderSide(color: VeraProbColors.error),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        // CANCELAR — retracts the dispute request (back to pending), no reason.
        Semantics(
          label: 'Cancelar solicitação de prova — devolve à fila de pendentes',
          child: TextButton.icon(
            onPressed: isLoading ? null : onRetract,
            icon: const Icon(Icons.undo, size: 16),
            label: const Text('CANCELAR SOLICITAÇÃO'),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
        ),
      ],
    );
  }
}

/// Zona 5 (pending_peer_review): dual-control confirm/decline for a high-value
/// verdict awaiting a SECOND auditor (Phase 10.5 Item 2).
///
/// The confirm button is DISABLED for the auditor who requested the verdict
/// ([isOwnRequest]) — the server enforces reviewer2 != reviewer1, and the UI
/// mirrors it so the requester never even attempts a self-confirmation.
class _PeerReviewRow extends StatelessWidget {
  final bool isLoading;
  final bool isOwnRequest;
  final String? proposedAction;
  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  const _PeerReviewRow({
    required this.isLoading,
    required this.isOwnRequest,
    required this.proposedAction,
    required this.onConfirm,
    required this.onDecline,
  });

  String get _actionLabel => switch (proposedAction) {
    'APPROVE' => 'Selar veredito (multa aplicada)',
    'REJECT' => 'Recusar veredito (multa anulada)',
    'OVERTURN' => 'Manter multa (disputa refutada)',
    'DISPUTE_ACCEPT' => 'Aceitar justificativa (multa anulada)',
    _ => 'Confirmar veredito',
  };

  @override
  Widget build(BuildContext context) {
    final confirmTooltip = isOwnRequest
        ? 'Você solicitou este veredito — outro auditor deve confirmar'
        : 'Confirmar como segundo auditor: $_actionLabel';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'AÇÃO PROPOSTA: ${_actionLabel.toUpperCase()}',
          style: VeraProbTypography.badge.copyWith(
            color: VeraProbColors.primary,
            fontSize: 9,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Semantics(
              label: confirmTooltip,
              child: Tooltip(
                message: confirmTooltip,
                child: FilledButton.icon(
                  onPressed: (isLoading || isOwnRequest) ? null : onConfirm,
                  icon: const Icon(Icons.how_to_reg_outlined, size: 16),
                  label: const Text('CONFIRMAR (2º AUDITOR)'),
                  style: FilledButton.styleFrom(
                    backgroundColor: VeraProbColors.success,
                    foregroundColor: VeraProbColors.background,
                    disabledBackgroundColor: VeraProbColors.textDisabled
                        .withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: isLoading ? null : onDecline,
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('RECUSAR REVISÃO'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VeraProbColors.textSecondary,
                side: const BorderSide(color: VeraProbColors.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ],
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

// ── Componente 4.2: dispute reason input + SLA chip + retraction provenance ──

/// Confirm-button gate (Componente 4.2): a structured [code] is mandatory; the
/// free-text complement is required (>= 10 chars) ONLY for the `OTHER` code.
/// Mirrors `ResolveDisputeHandler._assertReasonCode` so the UI never offers a
/// resolution the application layer would reject.
bool _disputeReasonSatisfied(String? code, TextEditingController controller) {
  if (code == null) return false;
  if (code == 'OTHER') return controller.text.trim().length >= 10;
  return true;
}

/// Inibir Violação gate (Componente 5.4): inhibiting a computed penalty ALWAYS
/// demands a written comment (>= 10 chars) on top of the structured code — a
/// forgiven fine carries human prose on record, never a rubber-stamp. Stricter
/// than [_disputeReasonSatisfied], which only forces prose for the `OTHER` code.
bool _inhibitionReasonSatisfied(
  String? code,
  TextEditingController controller,
) {
  if (code == null) return false;
  return controller.text.trim().length >= 10;
}

/// Structured reason selector for a dispute resolution arc (accept/overturn).
///
/// Surfaces the [DisputeReasonCodeDropdown] (B6 taxonomy) and reveals the
/// free-text field ONLY when `OTHER` is chosen — the 14 named codes are
/// self-describing, so forcing prose on them is friction (Q2). The free-text is
/// the human-readable description the handler then requires for `OTHER`.
class _DisputeReasonInput extends StatelessWidget {
  final bool isAccept;
  final String? selectedCode;
  final ValueChanged<String?> onCodeChanged;
  final TextEditingController freeTextController;

  const _DisputeReasonInput({
    required this.isAccept,
    required this.selectedCode,
    required this.onCodeChanged,
    required this.freeTextController,
  });

  @override
  Widget build(BuildContext context) {
    final isOther = selectedCode == 'OTHER';
    // Inibir Violação (5.4): the written comment is ALWAYS mandatory — forgiving
    // a computed fine demands human prose. Afirmar keeps free-text only for
    // `OTHER`, since the sealed hash is itself the upholding evidence.
    final showFreeText = isAccept || isOther;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DisputeReasonCodeDropdown(
          selectedCode: selectedCode,
          onChanged: onCodeChanged,
          label: isAccept
              ? 'Motivo da inibição (taxonomia)'
              : 'Motivo da afirmação (taxonomia)',
        ),
        if (!isAccept) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.lock_outline,
                size: 13,
                color: VeraProbColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Afirmar sela o hash da evidência — veredito imutável (INV-21).',
                  style: VeraProbTypography.caption.copyWith(
                    color: VeraProbColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
        if (showFreeText) ...[
          const SizedBox(height: 10),
          _RejectReasonField(
            controller: freeTextController,
            labelText: isAccept
                ? 'Comentário obrigatório (mínimo 10 caracteres)'
                : 'Descreva o motivo (mínimo 10 caracteres)',
          ),
        ],
      ],
    );
  }
}

/// SLA countdown chip for a `disputed` card (Componente 4.2c / 3 timer).
///
/// Reads `resolution_due_at`: green when comfortably ahead, amber within
/// [kDisputeSlaWarningDays], red "VENCIDA" once past due. Makes the auditor's
/// resolution deadline legible at a glance (the breach badge is the fleet-wide
/// counterpart).
class _DisputeSlaChip extends StatelessWidget {
  final DateTime dueAtUtc;
  const _DisputeSlaChip({required this.dueAtUtc});

  static String _humanize(Duration d) {
    final days = d.inDays;
    final hours = d.inHours % 24;
    if (days > 0) return '${days}d ${hours}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}min';
    return '${d.inMinutes}min';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final remaining = dueAtUtc.difference(now);
    final overdue = remaining.isNegative;
    final soon =
        !overdue && remaining <= const Duration(days: kDisputeSlaWarningDays);

    final color = overdue
        ? VeraProbColors.error
        : soon
        ? VeraProbColors.warning
        : VeraProbColors.onTime;
    final label = overdue
        ? 'SLA VENCIDA há ${_humanize(remaining.abs())}'
        : 'SLA: ${_humanize(remaining)} restantes';
    final icon = overdue
        ? Icons.alarm_off_outlined
        : soon
        ? Icons.alarm_outlined
        : Icons.timelapse_outlined;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Zona 4.3: provenance trail for a verdict that was disputed then retracted.
///
/// Shows WHO opened the contestation (kept on the queue row) and — enriched
/// from the `DISPUTE_RETRACTED` ledger fact — WHO cancelled it and the elapsed
/// gap. Keeps a cancelled dispute auditable (INV-23) instead of vanishing back
/// into the pending queue without a trace.
class _RetractionProvenanceZone extends ConsumerWidget {
  final SanctionQueueItemView item;
  const _RetractionProvenanceZone({required this.item});

  static String _shortActor(String? id) {
    if (id == null || id.trim().isEmpty) return 'desconhecido';
    final v = id.trim();
    return v.length <= 8 ? v : '${v.substring(0, 8)}…';
  }

  static String _formatLocal(DateTime utc) {
    final l = utc.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provenance = ref
        .watch(disputeRetractionProvenanceProvider(item.id))
        .value;

    final openedBy = _shortActor(item.disputedBy);
    final openedAt = item.disputedAtUtc;
    final retractedBy = _shortActor(provenance?.retractedBy);
    final retractedAt = provenance?.retractedAtUtc;
    final gap = (openedAt != null && retractedAt != null)
        ? _DisputeSlaChip._humanize(retractedAt.difference(openedAt).abs())
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: VeraProbColors.warning.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: VeraProbColors.warning.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.undo, size: 13, color: VeraProbColors.warning),
                const SizedBox(width: 6),
                Text(
                  'SOLICITAÇÃO RETRATADA',
                  style: VeraProbTypography.badge.copyWith(
                    color: VeraProbColors.warning,
                    fontSize: 9,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Aberta por $openedBy'
              '${openedAt != null ? ' em ${_formatLocal(openedAt)}' : ''}.',
              style: VeraProbTypography.bodyMedium.copyWith(
                fontSize: 12,
                color: VeraProbColors.textSecondary,
              ),
            ),
            Text(
              'Cancelada por $retractedBy'
              '${retractedAt != null ? ' em ${_formatLocal(retractedAt)}' : ''}'
              '${gap != null ? ' (após $gap)' : ''}.',
              style: VeraProbTypography.bodyMedium.copyWith(
                fontSize: 12,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
