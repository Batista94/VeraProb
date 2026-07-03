import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import 'package:veraprob/application/reporting/generate_forensic_dossier_handler.dart';
import 'package:veraprob/domain/reporting/forensic_dossier.dart';
import 'package:veraprob/application/sla_audit/projections/sanction_queue_item_view.dart';
import 'package:veraprob/application/sla_audit/resolve_dispute_command.dart'
    show DisputeResolution;
import 'package:veraprob/domain/sla_audit/verdict_evidence.dart'; // pr_scanner: ignore
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/shared/domain_error_text.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/forensic_dossier_modal.dart';
import 'package:veraprob/features/admin/presentation/shared/compliance_widgets.dart';
import 'package:veraprob/features/admin/presentation/shared/widgets/reverse_geocoded_address.dart';
import 'package:veraprob/application/dispute_portal/portal_submission_audit_gateway.dart';
import 'package:veraprob/state/providers/dispute_portal_providers.dart';
import 'package:veraprob/state/providers/dispute_portal_token_providers.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'package:veraprob/state/providers/reporting_providers.dart';
import 'package:veraprob/state/providers/sanction_focus_provider.dart';
import 'package:veraprob/state/providers/shared_providers.dart';
import 'package:veraprob/state/providers/telegram_providers.dart';

import 'ghost_bar_widget.dart';
import 'ingestion_health_widget.dart';
import 'recurrence_badge_widget.dart';
import 'risk_thermometer_widget.dart';
import 'sentence_panel_modal.dart';

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
  bool _isDossierLoading = false;
  String? _dossierError;
  String? _draftSentenceCode;
  String? _draftSentenceText;

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

    final now = ref.watch(dateTimeProviderProvider).nowUtc();
    final hasSlaRemaining =
        item.status == SanctionReviewStatus.disputed &&
        item.defenseSubmittedAt == null &&
        item.resolutionDueAtUtc != null &&
        item.resolutionDueAtUtc!.isAfter(now);

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
    // Focus is signalled by a tinted background + "NO MAPA" badge AND by widening
    // the full border into the SAME severity color as the left accent — never a
    // contrasting hue (a green outer border around an orange accent reads as a
    // bug). A pending verdict keeps its red severity cue even while selected.
    final Color leftBorderColor;
    const double leftBorderWidth = 3;
    if (item.status == SanctionReviewStatus.disputed) {
      leftBorderColor = VeraProbColors.warning;
    } else if (item.status == SanctionReviewStatus.pendingPeerReview) {
      leftBorderColor = VeraProbColors.primary;
    } else if (item.status == SanctionReviewStatus.rejected) {
      // Refused verdict: neutral slate — verdict sealed, no directional bias (INV-23).
      leftBorderColor = VeraProbColors.neutral.withValues(alpha: 0.5);
    } else if (item.status == SanctionReviewStatus.applied) {
      // Applied fine: red — confirmed penalty, carrier-adverse outcome.
      leftBorderColor = VeraProbColors.error;
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
                ? leftBorderColor.withValues(alpha: 0.05)
                : VeraProbColors.surface,
            borderRadius: VeraProbRadii.lgAll,
            border: Border.all(
              color: isFocused ? leftBorderColor : VeraProbColors.border,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // BUG-03: a tall verdict card (many forensic zones) used to push the
              // action buttons below the viewport with no way to reach them — the
              // card itself did not scroll. Bound the height and scroll the
              // content internally so the action row is always reachable.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.85,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildStatusRibbon(item, isLocked),
                    _buildIdentityStrip(item: item),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Zona 2: Financial Hero ─────────────────────────────────────
                            _buildFinancialHero(
                              context: context,
                              item: item,
                              displayName: displayName,
                              confidenceColor: confidenceColor,
                              isLoading: isLoading,
                            ),

                            const SizedBox(height: 16),
                            const Divider(
                              color: VeraProbColors.border,
                              height: 1,
                            ),

                            // ── Zona 3: Infraction Summary — Ghost Bars (WS-6) / VEL Details ────
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                              child:
                                  evidence.clauseRef
                                          .split('-')
                                          .first
                                          .toUpperCase() ==
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
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
                                      style: VeraProbTypography.caption
                                          .copyWith(
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
                                          color: VeraProbColors.primary
                                              .withValues(alpha: 0.12),
                                          borderRadius: VeraProbRadii.smAll,
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
                                              style: VeraProbTypography.badge
                                                  .copyWith(
                                                    color:
                                                        VeraProbColors.primary,
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
                                      .read(
                                        selectedSanctionFocusProvider.notifier,
                                      )
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
                                              evidence.geofenceRadiusMeters ??
                                              50.0,
                                        ),
                                      );
                                },
                              ),
                            ),

                            const SizedBox(height: 12),
                            const Divider(
                              color: VeraProbColors.border,
                              height: 1,
                            ),

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

                            const Divider(
                              color: VeraProbColors.border,
                              height: 1,
                            ),

                            // ── Zona 4: Forensic Seal ──────────────────────────────────────
                            _ForensicSealRow(item: item),

                            // ── Zona 4.3: Retraction provenance (re-pending verdicts) ─────
                            // A `pending` item carrying a non-null disputedAtUtc was
                            // disputed and later retracted — keep that trail visible
                            // (INV-23) so a cancelled contestation is never a silent ghost.
                            if (item.status == SanctionReviewStatus.pending &&
                                item.disputedAtUtc != null)
                              _RetractionProvenanceZone(item: item),

                            // ── Error feedback ─────────────────────────────────────────────
                            if (actionState is AsyncError ||
                                _dossierError != null) ...[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  12,
                                  20,
                                  0,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: VeraProbColors.error.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: VeraProbRadii.mdAll,
                                    border: Border.all(
                                      color: VeraProbColors.error.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.error_outline_rounded,
                                        color: VeraProbColors.error,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          actionState is AsyncError
                                              ? humanizeDomainError(
                                                  actionState.error,
                                                )
                                              : _dossierError!,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: VeraProbColors.error,
                                            height: 1.3,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                            if (item.status == SanctionReviewStatus.disputed)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  20,
                                  16,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (hasSlaRemaining) ...[
                                      _DisputeSlaChip(
                                        dueAtUtc: item.resolutionDueAtUtc!,
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    _PortalLinkZone(
                                      organizationId: item.organizationId,
                                      queueEntryId: item.id,
                                      defenseSubmittedAt:
                                          item.defenseSubmittedAt,
                                    ),
                                    const SizedBox(height: 12),
                                    _PortalSubmissionsZone(
                                      organizationId: item.organizationId,
                                      queueEntryId: item.id,
                                    ),
                                  ],
                                ),
                              ),
                            if (item.status == SanctionReviewStatus.applied ||
                                item.status == SanctionReviewStatus.rejected)
                              _buildForensicEvidenceVisualizerRow(
                                context,
                                item,
                              ),
                          ],
                        ),
                      ),
                    ),
                    // Sticky Footer Action Row
                    Container(
                      decoration: const BoxDecoration(
                        color: VeraProbColors.surface,
                        border: Border(
                          top: BorderSide(color: VeraProbColors.border),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      child: _buildStickyActionRow(
                        context,
                        item,
                        isLoading,
                        canSeal,
                        isOwnPeerRequest,
                        hasSlaRemaining,
                      ),
                    ),
                  ],
                ),
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
            ],
          ),
        ),
      ),
    );
  }

  /// In-flow status ribbon (formerly a floating `Positioned` overlay).
  ///
  /// Rendering it inside the scroll view fixes two defects at once: the badge
  /// no longer slides over the body on scroll, and it no longer covers the
  /// always-visible dossier button in the header. Returns an empty box for a
  /// plain pending card (severity is already carried by the left accent).
  Widget _buildStatusRibbon(SanctionQueueItemView item, bool isLocked) {
    final cfg = switch (item.status) {
      SanctionReviewStatus.applied => (
        color: VeraProbColors.error,
        icon: Icons.gavel_rounded,
        label: 'MULTA APLICADA',
        tooltip: 'Penalidade confirmada e aplicada — imutável',
        fill: 0.2,
        bordered: false,
      ),
      SanctionReviewStatus.disputed =>
        item.defenseSubmittedAt != null
            ? (
                color: VeraProbColors.warning,
                icon: Icons.mark_email_read_outlined,
                label: 'DEFESA RECEBIDA',
                tooltip:
                    'Transportadora enviou defesa — veredito do auditor pendente',
                fill: 0.2,
                bordered: false,
              )
            : (
                color: VeraProbColors.warning,
                icon: Icons.hourglass_empty_outlined,
                label: 'AGUARDANDO EVIDÊNCIA',
                tooltip: 'Evidência submetida. Resolva abaixo.',
                fill: 0.2,
                bordered: false,
              ),
      SanctionReviewStatus.pendingPeerReview => (
        color: VeraProbColors.primary,
        icon: Icons.groups_2_outlined,
        label: 'AGUARDANDO 2º AUDITOR',
        tooltip: 'Veredito de alto valor — requer um segundo auditor',
        fill: 0.15,
        bordered: true,
      ),
      SanctionReviewStatus.rejected => (
        color: VeraProbColors.neutral,
        icon: Icons.block_rounded,
        label: 'VEREDITO RECUSADO',
        tooltip: 'Sanção recusada — multa não aplicada',
        fill: 0.12,
        bordered: true,
      ),
      SanctionReviewStatus.acknowledged => (
        color: VeraProbColors.success,
        icon: Icons.verified_outlined,
        label: 'DE ACORDO',
        tooltip: 'Penalidade aceita pela transportadora (De Acordo)',
        fill: 0.15,
        bordered: true,
      ),
      _ =>
        isLocked
            ? (
                color: VeraProbColors.textDisabled,
                icon: Icons.lock,
                label: 'SELADO',
                tooltip: 'Veredito selado — Imutável (INV-7)',
                fill: 0.2,
                bordered: false,
              )
            : null,
    };

    if (cfg == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
      child: Row(
        children: [
          const Spacer(),
          Tooltip(
            message: cfg.tooltip,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: cfg.color.withValues(alpha: cfg.fill),
                borderRadius: VeraProbRadii.smAll,
                border: cfg.bordered
                    ? Border.all(color: cfg.color.withValues(alpha: 0.4))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(cfg.icon, size: 12, color: cfg.color),
                  const SizedBox(width: 4),
                  Text(
                    cfg.label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: cfg.color,
                      letterSpacing: 0.8,
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

  Widget _buildDossierButton() {
    if (_isDossierLoading) {
      return Container(
        height: 40,
        width: 40,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: VeraProbColors.surfaceElevated.withValues(alpha: 0.3),
          borderRadius: VeraProbRadii.mdAll,
          border: Border.all(color: VeraProbColors.border),
        ),
        child: const CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Tooltip(
      message: 'Baixar Dossiê PDF',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('download-dossier-button'),
          onTap: _onDownloadDossier,
          borderRadius: VeraProbRadii.mdAll,
          child: Container(
            height: 40,
            width: 40,
            decoration: BoxDecoration(
              color: VeraProbColors.surfaceElevated.withValues(alpha: 0.3),
              borderRadius: VeraProbRadii.mdAll,
              border: Border.all(color: VeraProbColors.border),
            ),
            child: const Icon(
              Icons.picture_as_pdf_outlined,
              size: 16,
              color: VeraProbColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialHero({
    required BuildContext context,
    required SanctionQueueItemView item,
    required String displayName,
    required Color confidenceColor,
    required bool isLoading,
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
                      color: switch (item.status) {
                        SanctionReviewStatus.applied => VeraProbColors.error,
                        SanctionReviewStatus.rejected =>
                          VeraProbColors.textDisabled,
                        _ => VeraProbColors.textPrimary,
                      },
                      decoration: item.status == SanctionReviewStatus.rejected
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: VeraProbColors.textDisabled,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDossierButton(),
              const SizedBox(width: 8),
              _ConfidenceBadge(
                score: item.verdictEvidence.confidenceScore,
                color: confidenceColor,
              ),
              if (item.status == SanctionReviewStatus.applied) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: VeraProbColors.textSecondary,
                  ),
                  tooltip: 'Mais opções',
                  enabled: !isLoading,
                  onSelected: (value) {
                    if (value == 'acknowledge_internal') {
                      _onAcknowledgeInternal(context);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'acknowledge_internal',
                      child: Text('Forçar Aceite Manual (Exceção)'),
                    ),
                  ],
                ),
              ],
            ],
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
                builder: (_) => ForensicDossierModal(
                  setId: item.setId,
                  contractId: item.contractId,
                  queueEntryId: item.id,
                ),
              ),
              icon: const Icon(Icons.shield_outlined, size: 16),
              label: const Text('Dossiê Forense'),
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

  Widget _buildStickyActionRow(
    BuildContext context,
    SanctionQueueItemView item,
    bool isLoading,
    bool canSeal,
    bool isOwnPeerRequest,
    bool hasSlaRemaining,
  ) {
    if (item.status == SanctionReviewStatus.pending) {
      final sealBlockedReason = canSeal
          ? 'Selar veredito — confirmar multa de ${item.formattedFine}'
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
                onPressed: (isLoading || !canSeal)
                    ? null
                    : () => _openSentencePanel(
                        context: context,
                        title: 'Confirmar Infração',
                        actionLabel: 'CONFIRMAR INFRAÇÃO',
                        actionColor: VeraProbColors.verdictAction,
                        showSlaWarning: false,
                        isAccept: false,
                        requireTextAlways: false,
                        onConfirm: (code, text) =>
                            _onApprove(context, code, text),
                      ),
                icon: isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          // ACCENT-FILL-CONTRAST: dark foreground on accent fill.
                          color: VeraProbColors.background,
                        ),
                      )
                    : const Icon(Icons.gavel_rounded, size: 16),
                label: const Text('CONFIRMAR INFRAÇÃO'),
                style: FilledButton.styleFrom(
                  backgroundColor: VeraProbColors.verdictAction,
                  foregroundColor: VeraProbColors.background,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          FilledButton.icon(
            onPressed: isLoading
                ? null
                : () => _openSentencePanel(
                    context: context,
                    title: 'Anular Infração',
                    actionLabel: 'ANULAR INFRAÇÃO',
                    actionColor: VeraProbColors.verdictAction,
                    showSlaWarning: false,
                    isAccept: true,
                    requireTextAlways: true,
                    onConfirm: (code, text) => _onReject(context, code, text),
                  ),
            icon: const Icon(Icons.block_rounded, size: 16),
            label: const Text('ANULAR INFRAÇÃO'),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.verdictAction,
              foregroundColor: VeraProbColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          Semantics(
            label: 'Solicitar prova forense ao motorista',
            child: OutlinedButton.icon(
              onPressed: isLoading ? null : () => _onRequestMoreProof(context),
              icon: const Icon(Icons.find_in_page_outlined, size: 16),
              label: const Text('SOLICITAR DEFESA'),
              style: OutlinedButton.styleFrom(
                foregroundColor: VeraProbColors.textSecondary,
                side: const BorderSide(color: VeraProbColors.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ],
      );
    } else if (item.status == SanctionReviewStatus.disputed) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton.icon(
            onPressed: isLoading
                ? null
                : () => _openSentencePanel(
                    context: context,
                    title: 'Anular Infração',
                    actionLabel: 'ANULAR INFRAÇÃO',
                    actionColor: VeraProbColors.verdictAction,
                    showSlaWarning: hasSlaRemaining,
                    isAccept: true,
                    requireTextAlways: true,
                    onConfirm: (code, text) => _onAcceptDispute(code, text),
                  ),
            icon: const Icon(Icons.check_circle_outline, size: 16),
            label: const Text('ANULAR INFRAÇÃO'),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.verdictAction,
              foregroundColor: VeraProbColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          FilledButton.icon(
            onPressed: isLoading
                ? null
                : () => _openSentencePanel(
                    context: context,
                    title: 'Confirmar Infração',
                    actionLabel: 'CONFIRMAR INFRAÇÃO',
                    actionColor: VeraProbColors.verdictAction,
                    showSlaWarning: hasSlaRemaining,
                    isAccept: false,
                    requireTextAlways: false,
                    onConfirm: (code, text) => _onRefuseDispute(code, text),
                  ),
            icon: const Icon(Icons.gavel_rounded, size: 16),
            label: const Text('CONFIRMAR INFRAÇÃO'),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.verdictAction,
              foregroundColor: VeraProbColors.background,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
          ),
          if (item.defenseSubmittedAt == null)
            Semantics(
              label:
                  'Cancelar solicitação de prova — devolve à fila de pendentes',
              child: TextButton.icon(
                onPressed: isLoading ? null : _onRetractDispute,
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Cancelar solicitação'),
                style: TextButton.styleFrom(
                  foregroundColor: VeraProbColors.textSecondary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
        ],
      );
    } else if (item.status == SanctionReviewStatus.pendingPeerReview) {
      return _PeerReviewRow(
        isLoading: isLoading,
        isOwnRequest: isOwnPeerRequest,
        proposedAction: item.peerReviewProposedAction,
        onConfirm: () => _onConfirmPeerReview(context),
        onDecline: () => _onDeclinePeerReview(context),
      );
    }
    return const SizedBox.shrink();
  }

  void _openSentencePanel({
    required BuildContext context,
    required String title,
    required String actionLabel,
    required Color actionColor,
    required bool showSlaWarning,
    required bool isAccept,
    required bool requireTextAlways,
    required Future<void> Function(String, String) onConfirm,
  }) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => SentencePanelModal(
        title: title,
        actionLabel: actionLabel,
        actionColor: actionColor,
        showSlaWarning: showSlaWarning,
        isAccept: isAccept,
        requireTextAlways: requireTextAlways,
        initialCode: _draftSentenceCode,
        initialText: _draftSentenceText,
        onChanged: (code, text) {
          _draftSentenceCode = code;
          _draftSentenceText = text;
        },
        onConfirm: onConfirm,
      ),
    );
  }

  Future<void> _onApprove(
    BuildContext context,
    String reasonCode,
    String reasonText,
  ) async {
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
    final trimmedReason = reasonText.trim();
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .approve(
          queueEntryId: widget.item.id,
          approvedByUserId: userId,
          actorEmail: email,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
          reasonCode: reasonCode,
          reviewerReason: trimmedReason.isEmpty ? null : trimmedReason,
        );
    // Force stream re-query so the card disappears without requiring a second click.
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncError) {
      // Re-surface to the SentencePanelModal so it stays open, shows the domain
      // error and preserves the auditor's reason code + comment (transactional
      // submit — the guarded notifier captures the error rather than rethrowing).
      throw actionState.error;
    }
    if (actionState is AsyncData) {
      ref.invalidate(pendingSanctionsStreamProvider);
    }
  }

  /// Records an off-band "De Acordo" for this applied sanction (TENANT_ADMIN
  /// documents that the carrier accepted by email/phone). Terminal + irreversible
  /// → explicit confirmation with optional notes before the call.
  Future<void> _onAcknowledgeInternal(BuildContext context) async {
    // Lesson 8: capture context-bound objects before the first await.
    final messenger = ScaffoldMessenger.of(context);
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    final role = ref.read(currentUserRoleProvider);

    final notesController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: VeraProbColors.surface,
        title: const Text('Registrar De Acordo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirma que a transportadora aceitou esta penalidade '
              '(${'aceite off-band: e-mail/telefone'})? Esta ação é '
              'definitiva e sela a sanção como "De Acordo".',
              style: TextStyle(
                fontSize: 13,
                color: VeraProbColors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesController,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observações (opcional)',
                hintText: 'Ex.: aceite por e-mail de 12/06, ref. #4821',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: VeraProbColors.success,
            ),
            child: const Text('Confirmar De Acordo'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      notesController.dispose();
      return;
    }
    final notes = notesController.text.trim();
    notesController.dispose();

    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .acknowledgeInternal(
          queueEntryId: widget.item.id,
          acknowledgedByUserId: userId,
          notes: notes.isEmpty ? null : notes,
          callerRole: role,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
        );
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncData) {
      // Item leaves the verdicts lane (`applied`) and enters the "De Acordo"
      // lane (`acknowledged`) — refresh both terminal lanes.
      ref.invalidate(sealedSanctionsNotifierProvider(TerminalLane.verdicts));
      ref.invalidate(
        sealedSanctionsNotifierProvider(TerminalLane.acknowledged),
      );
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(content: Text('De Acordo registrado e selado.')),
        );
      }
    }
  }

  Future<void> _onReject(
    BuildContext context,
    String reasonCode,
    String reasonText,
  ) async {
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final email = ref.read(currentOperatorEmailProvider);
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    await ref
        .read(sanctionActionStateProvider(widget.item.id).notifier)
        .reject(
          queueEntryId: widget.item.id,
          rejectedByUserId: userId,
          actorEmail: email,
          rejectionReason: reasonText,
          reasonCode: reasonCode,
          callerRole: UserRole.auditor,
          organizationId: widget.item.organizationId,
          sessionId: sessionId,
        );
    final actionState = ref.read(sanctionActionStateProvider(widget.item.id));
    if (actionState is AsyncError) {
      throw actionState.error;
    }
    if (actionState is AsyncData) {
      ref.invalidate(pendingSanctionsStreamProvider);
    }
  }

  Future<void> _onRequestMoreProof(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
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
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Solicitação enviada. Motorista será notificado para enviar prova forense.',
          ),
        ),
      );
    }
  }

  // Modal-driven arcs: rethrow the guarded notifier's captured failure so the
  // SentencePanelModal stays open and preserves the auditor's input. Retract is
  // a direct (non-modal) button, so it surfaces via the card-level banner.
  Future<void> _onAcceptDispute(String reasonCode, String reasonText) async {
    await _resolveDispute(DisputeResolution.accept, reasonText, reasonCode);
    _throwIfActionFailed();
  }

  Future<void> _onRefuseDispute(String reasonCode, String reasonText) async {
    await _resolveDispute(DisputeResolution.overturn, reasonText, reasonCode);
    _throwIfActionFailed();
  }

  Future<void> _onRetractDispute() =>
      _resolveDispute(DisputeResolution.retract, null, null);

  void _throwIfActionFailed() {
    final state = ref.read(sanctionActionStateProvider(widget.item.id));
    if (state is AsyncError) {
      throw state.error;
    }
  }

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

    if (userId.isEmpty) {
      setState(
        () => _dossierError =
            'Sessão expirada. Recarregue a página e tente novamente.',
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _isDossierLoading = true;
      _dossierError = null;
    });

    try {
      final provenance = await ref.read(
        verdictProvenanceProvider(item.id).future,
      );

      final classification = switch (item.status) {
        SanctionReviewStatus.applied => DossierClassification.applied,
        SanctionReviewStatus.rejected => DossierClassification.annulled,
        SanctionReviewStatus.acknowledged => DossierClassification.acknowledged,
        _ => DossierClassification.preliminary,
      };
      final sealed = classification != DossierClassification.preliminary;
      final outcomeLabel = switch (item.status) {
        SanctionReviewStatus.applied => 'INFRAÇÃO CONFIRMADA',
        SanctionReviewStatus.rejected => 'INFRAÇÃO ANULADA',
        SanctionReviewStatus.acknowledged =>
          'DE ACORDO (ACEITE DO TRANSPORTADOR)',
        _ => null,
      };
      final auditorNoteText =
          provenance?.auditorNote?.trim() ?? item.rejectionReason?.trim();

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
        classification: classification,
        verdictOutcomeLabel: outcomeLabel,
        auditorReasonCode: item.rejectionReasonCode?.trim(),
        auditorNote: (auditorNoteText != null && auditorNoteText.isNotEmpty)
            ? auditorNoteText
            : null,
        verdictSealHash: sealed ? evidence.evidenceHash : null,
      );

      final handler = ref.read(generateForensicDossierHandlerProvider);
      final bytes = await handler.handle(command);
      final prefix = sealed ? 'dossie_selado' : 'dossie_preliminar';
      final name =
          '${prefix}_'
          '${item.ledgerEntryId.substring(0, 8)}_'
          '${DateTime.now().toUtc().millisecondsSinceEpoch}';
      await FileSaver.instance.saveFile(
        name: name,
        bytes: Uint8List.fromList(bytes),
        fileExtension: 'pdf',
        mimeType: MimeType.pdf,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sealed
                ? 'Dossiê selado (VEREDITO SELADO) baixado com sucesso.'
                : 'Dossiê preliminar baixado — marca d\'água "PRELIMINAR".',
          ),
        ),
      );
    } catch (e) {
      LoggerService().error('dossier_download_failed', error: e);
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
        borderRadius: VeraProbRadii.mdAll,
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
      AsyncData(:final value) => _buildContent(value),
    };
  }

  Widget _buildContent(({DateTime start, DateTime end})? value) {
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

    final key =
        '${item.id}|$plate|${item.organizationId}|${item.createdAtUtc.toIso8601String()}';
    return switch (ref.watch(vehicleInfractionRecurrenceProvider(key))) {
      AsyncLoading() => const SizedBox(height: 48),
      AsyncError() => const SizedBox.shrink(),
      AsyncData(:final value) =>
        value == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: RecurrenceBadgeWidget(report: value),
              ),
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
        borderRadius: VeraProbRadii.smAll,
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
        borderRadius: VeraProbRadii.mdAll,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: VeraProbColors.surfaceElevated.withValues(alpha: 0.5),
            borderRadius: VeraProbRadii.smAll,
          ),
          child: Text(
            'SHA-256: ${item.shortEvidenceHash}...',
            style: VeraProbTypography.caption.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
              color: VeraProbColors.textDisabled,
            ),
          ),
        ),
      ),
    );
  }
}

/// Zona 5 (disputed): inline Human Verdict Affirmation controls for a contested
/// verdict (Componente 5.4).
///
/// Mirrors [_VerdictActionRow] but closes the dispute loop (INV-23) with a
/// differentiated human signature — never a rubber-stamp:
/// - MANTER MULTA → `disputed → applied` (fine upheld; seals the evidence
///   hash inline, INV-21), structured reason code (free-text only for `OTHER`).
/// - ANULAR MULTA → `disputed → rejected` (fine forgiven), structured reason
///   code AND a mandatory written comment (≥10) — forgiving a computed penalty
///   must carry human prose on record.
/// - CANCELAR SOLICITAÇÃO → `disputed → pending` (retract), no reason.
///
/// Inline (not modal) to avoid `barrierDismissible:false` stacking (Lesson 4)
/// and preserve map focus.

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
            color: VeraProbColors.warning,
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
                    backgroundColor: VeraProbColors.verdictAction,
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
      AsyncData(:final value) =>
        value == null
            ? const SizedBox.shrink()
            : Padding(
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
              ),
    };
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
          borderRadius: VeraProbRadii.mdAll,
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

/// Zona 4.25: Verdict accountability (INV-21).
///
/// Auditor review of carrier-submitted counter-evidence awaiting a verdict.
///
/// Lists `PENDING_AUDIT` portal submissions for this disputed sanction via the
/// deny-all-safe `list_portal_submissions` RPC, exposing one-click ACEITAR /
/// REJEITAR per file (`audit_portal_submission`). Hidden entirely when no portal
/// evidence is pending — the legacy in-app dispute flow is unaffected.
/// BUG-02 — Auditor-facing control to MINT a carrier portal link for a
/// contested sanction. The `generate_dispute_portal_token` RPC exists in the DB
/// but had no Dart caller, so `dispute_portal_tokens` was always empty and the
/// carrier never received an access link. This zone wires the missing path.
///
/// On success the opaque token is rendered as a copyable
/// `/portal/dispute?token=<uuid>` URL the auditor hands to the carrier.
class _PortalLinkZone extends ConsumerStatefulWidget {
  final String organizationId;
  final String queueEntryId;

  /// Write-once instant the carrier submitted a portal defense. When non-null
  /// the link is permanently sealed server-side (token revoked on submit), so
  /// the management affordance (copy/regenerate/generate) must disappear — the
  /// only honest state is read-only "defesa recebida — link encerrado".
  final DateTime? defenseSubmittedAt;

  const _PortalLinkZone({
    required this.organizationId,
    required this.queueEntryId,
    required this.defenseSubmittedAt,
  });

  @override
  ConsumerState<_PortalLinkZone> createState() => _PortalLinkZoneState();
}

class _PortalLinkZoneState extends ConsumerState<_PortalLinkZone> {
  String _portalUrl(String token) {
    final base = Uri.base;
    // `Uri.origin` only accepts http/https; outside the web runtime (e.g. tests)
    // fall back to a relative path so the link is still rendered/copyable.
    final origin = (base.scheme == 'http' || base.scheme == 'https')
        ? base.origin
        : '';
    return '$origin/portal/dispute?token=$token';
  }

  Future<void> _generate() async {
    final messenger = ScaffoldMessenger.of(context);
    final userId = ref.read(currentOperatorIdProvider) ?? '';
    final email = ref.read(currentOperatorEmailProvider);
    final sessionId = ref.read(currentSessionIdProvider) ?? '';
    final token = await ref
        .read(disputePortalTokenProvider(widget.queueEntryId).notifier)
        .generate(
          createdByUserId: userId,
          actorEmail: email,
          callerRole: UserRole.auditor,
          organizationId: widget.organizationId,
          sessionId: sessionId,
        );
    if (!mounted || token == null) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('Link de disputa gerado.')),
    );
  }

  Future<void> _copy(String url) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Link copiado para a área de transferência.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Defense already on file → the portal link is sealed (token revoked on
    // submit). Render a read-only terminal state and suppress every link
    // affordance, regardless of any stale in-memory token (Bug 2-B). This also
    // closes the anti-forensic vector of re-issuing/cancelling a link to mask a
    // received defense (mirrors the write-once DB guard).
    if (widget.defenseSubmittedAt != null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: VeraProbColors.surfaceElevated,
          borderRadius: VeraProbRadii.mdAll,
          border: Border.all(color: VeraProbColors.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.lock_outline,
              size: 16,
              color: VeraProbColors.textDisabled,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Defesa recebida — link encerrado',
                style: VeraProbTypography.bodySmall.copyWith(
                  color: VeraProbColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final tokenState = ref.watch(
      disputePortalTokenProvider(widget.queueEntryId),
    );
    final isLoading = tokenState is AsyncLoading;
    final token = switch (tokenState) {
      AsyncData(:final value) => value,
      _ => null,
    };

    if (token != null) {
      final url = _portalUrl(token);
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: VeraProbColors.surfaceElevated,
          borderRadius: VeraProbRadii.mdAll,
          border: Border.all(color: VeraProbColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Link de disputa do transportador',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.textSecondary,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    url,
                    key: const ValueKey('dispute-portal-url'),
                    maxLines: 2,
                    style: const TextStyle(
                      fontSize: 12,
                      color: VeraProbColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _copy(url),
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('Copiar Link'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () => _generate(),
                  icon: const Icon(Icons.refresh, size: 14),
                  label: const Text('Regerar'),
                  style: TextButton.styleFrom(
                    foregroundColor: VeraProbColors.textSecondary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: isLoading ? null : _generate,
        icon: isLoading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.link_rounded, size: 16),
        label: const Text('GERAR LINK DE DISPUTA'),
        style: OutlinedButton.styleFrom(
          foregroundColor: VeraProbColors.accent,
          side: const BorderSide(color: VeraProbColors.accent),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );
  }
}

class _PortalSubmissionsZone extends ConsumerStatefulWidget {
  final String organizationId;
  final String queueEntryId;
  const _PortalSubmissionsZone({
    required this.organizationId,
    required this.queueEntryId,
  });

  @override
  ConsumerState<_PortalSubmissionsZone> createState() =>
      _PortalSubmissionsZoneState();
}

class _PortalSubmissionsZoneState
    extends ConsumerState<_PortalSubmissionsZone> {
  ({String orgId, String queueEntryId}) get _key =>
      (orgId: widget.organizationId, queueEntryId: widget.queueEntryId);

  @override
  Widget build(BuildContext context) {
    // INV-16: a single shared realtime channel feeds every disputed card. When a
    // NEW counter-evidence attachment lands for THIS dispute (count delta on its
    // queueEntryId), re-fetch the pending submissions so the auditor sees the
    // contraprova live — no manual reload, no per-card subscription.
    final queueEntryId = widget.queueEntryId;
    ref.listen(portalEvidenceRealtimeProvider, (prev, next) {
      // Skip until we hold a prior data snapshot (the initial loading→data
      // emission has no `before` to diff against).
      final before = switch (prev) {
        AsyncData(:final value) => value[queueEntryId] ?? 0,
        _ => null,
      };
      if (before == null) return;
      final after = switch (next) {
        AsyncData(:final value) => value[queueEntryId] ?? 0,
        _ => before,
      };
      if (after != before) {
        ref.invalidate(pendingPortalSubmissionsProvider(_key));
        ref.invalidate(pendingPortalJustificationsProvider(_key));
      }
    });

    final files =
        ref.watch(pendingPortalSubmissionsProvider(_key)).value ??
        const <PortalSubmissionSummary>[];
    final testimonies =
        ref.watch(pendingPortalJustificationsProvider(_key)).value ??
        const <PortalJustificationSummary>[];

    if (files.isEmpty && testimonies.isEmpty) return const SizedBox.shrink();
    final total = files.length + testimonies.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_upload_outlined,
                size: 13,
                color: VeraProbColors.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EVIDÊNCIAS DA DEFESA ($total)',
                      style: VeraProbTypography.badge.copyWith(
                        color: VeraProbColors.primary,
                        fontSize: 9,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Revisar antes de emitir veredito',
                      style: VeraProbTypography.caption.copyWith(
                        color: VeraProbColors.textDisabled,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...files.map((s) => _PortalSubmissionTile(summary: s)),
          ...testimonies.map((j) => _PortalJustificationTile(summary: j)),
        ],
      ),
    );
  }
}

/// Provenance marker: this evidence arrived via the external dispute portal
/// (anon submitter), not an internal auditor upload. Forensic chain-of-custody
/// demands the origin be visible at a glance (INV-23).
class _PortalProvenanceBadge extends StatelessWidget {
  const _PortalProvenanceBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Origem: Portal de Contestação (submissão externa)',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: VeraProbColors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(
            color: VeraProbColors.primary.withValues(alpha: 0.3),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_done_outlined,
              size: 10,
              color: VeraProbColors.primary,
            ),
            const SizedBox(width: 3),
            Text(
              'PORTAL',
              style: VeraProbTypography.badge.copyWith(
                color: VeraProbColors.primary,
                fontSize: 8,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalSubmissionTile extends StatelessWidget {
  final PortalSubmissionSummary summary;

  const _PortalSubmissionTile({required this.summary});

  String _humanSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final hash = summary.sha256Server;
    final shortHash = (hash != null && hash.length >= 12)
        ? '${hash.substring(0, 12)}…'
        : (hash ?? '—');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _PortalProvenanceBadge(),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  summary.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VeraProbTypography.dataValue.copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _humanSize(summary.fileSizeBytesActual),
                style: VeraProbTypography.caption.copyWith(fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'SHA-256: $shortHash · ${summary.mimeTypeDetected ?? '—'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: VeraProbTypography.caption.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
              color: VeraProbColors.textDisabled,
            ),
          ),
          if (summary.attachmentId != null) ...[
            const SizedBox(height: 8),
            _PortalAttachmentThumb(
              attachmentId: summary.attachmentId!,
              fileName: summary.fileName,
              mimeType: summary.mimeTypeDetected,
              sha256: summary.sha256Server,
              fileSizeBytes: summary.fileSizeBytesActual,
            ),
          ],
          if (summary.justificationText case final String t
              when t.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _TestimonyBlock(text: t),
          ],
        ],
      ),
    );
  }
}

/// Read-only tile for a testimony-only (file-optional) portal contest. There is
/// no file to view and nothing to accept/reject per item — the auditor weighs it
/// when resolving the dispute. Sealed via SHA-256 (INV-9).
class _PortalJustificationTile extends StatelessWidget {
  final PortalJustificationSummary summary;
  const _PortalJustificationTile({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VeraProbColors.surfaceElevated,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const _PortalProvenanceBadge(),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Defesa textual (sem anexo)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VeraProbTypography.caption.copyWith(fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _TestimonyBlock(
            text: summary.justificationText,
            sha256: summary.sha256JustificationSeal,
          ),
        ],
      ),
    );
  }
}

/// Carrier testimony block — the written justification, rendered raw (escaped by
/// Flutter Text, never at ingest). Collapses past 4 lines behind "Ver mais".
/// Optionally shows the testimony seal (INV-9) with a copy affordance.
class _TestimonyBlock extends StatefulWidget {
  final String text;
  final String? sha256;
  const _TestimonyBlock({required this.text, this.sha256});

  @override
  State<_TestimonyBlock> createState() => _TestimonyBlockState();
}

class _TestimonyBlockState extends State<_TestimonyBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final seal = widget.sha256;
    final shortSeal = (seal != null && seal.length >= 12)
        ? '${seal.substring(0, 12)}…'
        : seal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: const Border(
          left: BorderSide(color: VeraProbColors.primary, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'JUSTIFICATIVA DA CONTESTAÇÃO',
            style: VeraProbTypography.badge.copyWith(
              color: VeraProbColors.primary,
              fontSize: 8,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: Text(
              widget.text,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: VeraProbTypography.bodySmall.copyWith(fontSize: 12),
            ),
            secondChild: Text(
              widget.text,
              style: VeraProbTypography.bodySmall.copyWith(fontSize: 12),
            ),
          ),
          if (widget.text.length > 160)
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _expanded ? 'Ver menos' : 'Ver mais',
                  style: VeraProbTypography.caption.copyWith(
                    color: VeraProbColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          if (shortSeal != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Selo: $shortSeal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VeraProbTypography.caption.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: VeraProbColors.textDisabled,
                    ),
                  ),
                ),
                Semantics(
                  button: true,
                  label: 'Copiar selo da justificativa',
                  child: InkWell(
                    onTap: () {
                      final messenger = ScaffoldMessenger.of(context);
                      Clipboard.setData(ClipboardData(text: seal!));
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Selo copiado.')),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.copy_rounded,
                        size: 13,
                        color: VeraProbColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 64×64 thumbnail for a dispute attachment, served via the JWT-gated
/// `auditor-dispute-evidence` proxy (INV-26). Tapping opens a fullscreen
/// lightbox. Non-image formats show a document glyph (no inline preview).
class _PortalAttachmentThumb extends ConsumerWidget {
  final String attachmentId;
  final String fileName;
  final String? mimeType;
  final String? sha256;
  final int? fileSizeBytes;

  const _PortalAttachmentThumb({
    required this.attachmentId,
    required this.fileName,
    required this.mimeType,
    required this.sha256,
    required this.fileSizeBytes,
  });

  bool get _isImage => (mimeType ?? '').startsWith('image/');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = ref
        .read(evidenceUrlServiceProvider)
        .getDisputeAttachmentProxyUrl(attachmentId);
    final token = ref.watch(currentSessionIdProvider) ?? '';

    final preview = _isImage
        ? CachedNetworkImage(
            imageUrl: url,
            httpHeaders: {'Authorization': 'Bearer $token'},
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            placeholder: (_, _) => _glyph(Icons.image_outlined),
            errorWidget: (_, _, _) => _glyph(Icons.broken_image_outlined),
          )
        : _glyph(Icons.picture_as_pdf_outlined);

    return Semantics(
      button: true,
      label: 'Abrir anexo da contestação',
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          barrierColor: const Color(0xDE000000), // lightbox barrier
          builder: (_) => _PortalAttachmentLightbox(
            url: url,
            token: token,
            fileName: fileName,
            mimeType: mimeType,
            sha256: sha256,
            fileSizeBytes: fileSizeBytes,
            isImage: _isImage,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: preview,
        ),
      ),
    );
  }

  Widget _glyph(IconData icon) => Container(
    width: 64,
    height: 64,
    color: VeraProbColors.surface,
    alignment: Alignment.center,
    child: Icon(icon, size: 26, color: VeraProbColors.textSecondary),
  );
}

/// Fullscreen viewer for a dispute attachment. Images are zoomable; other
/// formats show metadata only (inline preview needs a viewer dep — out of
/// scope). Footer carries SHA-256 + size + MIME (INV-9 provenance).
class _PortalAttachmentLightbox extends StatelessWidget {
  final String url;
  final String token;
  final String fileName;
  final String? mimeType;
  final String? sha256;
  final int? fileSizeBytes;
  final bool isImage;

  const _PortalAttachmentLightbox({
    required this.url,
    required this.token,
    required this.fileName,
    required this.mimeType,
    required this.sha256,
    required this.fileSizeBytes,
    required this.isImage,
  });

  String _humanSize(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.topRight,
            child: Semantics(
              button: true,
              label: 'Fechar visualização',
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(
                  Icons.close,
                  color: VeraProbColors.textPrimary,
                ),
              ),
            ),
          ),
          Flexible(
            child: isImage
                ? InteractiveViewer(
                    maxScale: 5,
                    child: CachedNetworkImage(
                      imageUrl: url,
                      httpHeaders: {'Authorization': 'Bearer $token'},
                      fit: BoxFit.contain,
                      placeholder: (_, _) => const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (_, _, _) => const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'Não foi possível carregar o anexo.',
                          style: TextStyle(color: VeraProbColors.textPrimary),
                        ),
                      ),
                    ),
                  )
                : Container(
                    padding: const EdgeInsets.all(32),
                    color: VeraProbColors.surface,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.picture_as_pdf_outlined,
                          size: 56,
                          color: VeraProbColors.textSecondary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          fileName,
                          textAlign: TextAlign.center,
                          style: VeraProbTypography.dataValue,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Visualização inline indisponível para este formato.',
                          textAlign: TextAlign.center,
                          style: VeraProbTypography.caption,
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: VeraProbColors.background.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: VeraProbTypography.dataValue.copyWith(fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  '${mimeType ?? '—'} · ${_humanSize(fileSizeBytes)}',
                  style: VeraProbTypography.caption.copyWith(fontSize: 10),
                ),
                if (sha256 != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'SHA-256: $sha256',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VeraProbTypography.caption.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: VeraProbColors.textDisabled,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
