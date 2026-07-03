import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade/alert_card_atoms.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade/dispute_defense_card.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/evidence_dossier_modal.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_category_chip.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_link_source_chip.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

/// Rich evidence card for a single operational alert.
///
/// Features: evidence peek thumbnails (INV-26 proxy-only), collision
/// awareness (viewed-by-others badge, unread dimming), quick actions.
class RichEvidenceCard extends ConsumerWidget {
  final OperationalAlert alert;

  const RichEvidenceCard({super.key, required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A carrier defense submission is its own card: it deep-links the auditor
    // to the disputed lane instead of the SLA reconciliation flow.
    if (alert.alertType == 'DISPUTE_DEFENSE_SUBMITTED') {
      return DisputeDefenseCard(alert: alert);
    }

    final severityColor = _severityColor(alert.severity);
    final timeAgo = formatAlertTimeAgo(alert.triggeredAtUtc);
    final currentUserId = ref.watch(currentOperatorIdProvider);

    // TASK 2: Collision awareness — unread = not viewed by current user
    final isUnread =
        currentUserId != null && !alert.viewedByUserIds.contains(currentUserId);
    final isViewedByOthers = alert.viewedByUserIds.any(
      (uid) => uid != currentUserId,
    );
    final evidenceIds = _extractEvidenceIds(alert);

    final card = Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: VeraProbColors.surface,
        borderRadius: VeraProbRadii.mdAll,
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: type + severity + time ──
          Row(
            children: [
              AlertSeverityBadge(
                label: _alertTypeLabel(alert.alertType),
                color: severityColor,
              ),
              if (alert.context['evidence_category'] case final String cat) ...[
                const SizedBox(width: 6),
                EvidenceCategoryChip(category: cat),
              ],
              if (alert.context['link_source'] case final String src) ...[
                const SizedBox(width: 6),
                EvidenceLinkSourceChip(source: src),
              ],
              if (evidenceIds.length > 1) ...[
                const SizedBox(width: 6),
                AlertPhotoCountBadge(count: evidenceIds.length),
              ],
              const Spacer(),
              // TASK 2: 👀 badge when viewed by another operator
              if (isViewedByOthers)
                const Tooltip(
                  message: 'Sendo tratado por outro operador',
                  child: Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.visibility_outlined,
                      size: 12,
                      color: VeraProbColors.textSecondary,
                    ),
                  ),
                ),
              Text(timeAgo, style: alertTimestampStyle()),
            ],
          ),
          const SizedBox(height: 8),
          // ── Body: evidence peek (INV-26: proxy-only) ──
          _EvidencePeekWidget(evidenceIds: evidenceIds),
          const SizedBox(height: 6),
          // ── Gap label / forensic hash ──
          Row(
            children: [
              if (alert.context['forensic_hash_prefix'] != null) ...[
                Text(
                  '🔐 ${alert.context['forensic_hash_prefix']}…',
                  style: VeraProbTypography.caption.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 10,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  _gapLabel(alert),
                  style: VeraProbTypography.bodySmall.copyWith(
                    color: severityColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── Footer: Quick Actions ──
          Row(
            children: [
              Expanded(
                child: AlertActionButton(
                  label:
                      (alert.alertType == 'TELEMETRY_SILENT' ||
                          alert.alertType == 'EVIDENCE_GAP')
                      ? 'Diagnóstico'
                      : 'Reconciliar',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () {
                    if (alert.alertType == 'TELEMETRY_SILENT' ||
                        alert.alertType == 'EVIDENCE_GAP') {
                      Navigator.of(context).pop();
                      context.go(
                        AppRoutes.ingestionHealthVehicle(alert.entityId),
                      );
                    } else {
                      ref
                          .read(selectedContractIdProvider.notifier)
                          .set(alert.contractId);
                      Navigator.of(context).pop();
                      context.go(AdminNav.slaAudit.path);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              if (alert.alertType == 'TELEGRAM_ORPHAN' &&
                  alert.context['driver_id'] != null)
                Expanded(
                  child: _QuickLinkButton(
                    alert: alert,
                    evidenceIds: evidenceIds,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    // TASK 2: Dim unread cards + collision indicator
    if (isUnread) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Opacity(opacity: 0.6, child: card),
          Positioned(
            top: 4,
            right: 4,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              child: const Icon(
                Icons.visibility_outlined,
                size: 12,
                color: VeraProbColors.textSecondary,
              ),
            ),
          ),
        ],
      );
    }
    return card;
  }

  static String? _extractEvidenceId(OperationalAlert alert) {
    final deepLink = alert.context['deep_link'] as String?;
    if (deepLink == null) return null;
    final uri = Uri.tryParse(deepLink);
    if (uri == null || uri.pathSegments.isEmpty) return null;
    return uri.pathSegments.last;
  }

  /// Returns the full list of evidence IDs for this alert.
  ///
  /// Reads `context['evidence_ids']` (accumulated by the flood-suppression
  /// trigger after the 20260613 migration). Falls back to the single
  /// `context['evidence_id']` or the deep_link path for legacy alerts.
  static List<String> _extractEvidenceIds(OperationalAlert alert) {
    final ids = alert.context['evidence_ids'];
    if (ids is List && ids.isNotEmpty) {
      return ids.whereType<String>().toList();
    }
    // Fallback: legacy single-photo alert
    final single =
        alert.context['evidence_id'] as String? ?? _extractEvidenceId(alert);
    return single != null ? [single] : [];
  }

  static String _gapLabel(OperationalAlert alert) {
    final windowStart = alert.context['window_start'] as String?;
    if (windowStart != null) {
      try {
        final start = DateTime.parse(windowStart);
        final gap = alert.triggeredAtUtc.difference(start);
        if (gap.inMinutes > 0) return 'Atraso de ${gap.inMinutes}min';
      } catch (_) {}
    }
    return _alertTypeLabel(alert.alertType);
  }

  static Color _severityColor(String severity) {
    return switch (severity) {
      'CRITICAL' => VeraProbColors.critical,
      'HIGH' => VeraProbColors.delayed,
      _ => VeraProbColors.textSecondary,
    };
  }

  static String _alertTypeLabel(String alertType) {
    return switch (alertType) {
      'NO_SHOW' => 'NO-SHOW',
      'EVIDENCE_GAP' => 'EVIDÊNCIA',
      'PENALTY_APPLIED' => 'PENALIDADE',
      'TELEGRAM_ORPHAN' => 'FOTO ÓRFÃ',
      'DISPUTE_DEFENSE_SUBMITTED' => 'CONTESTAÇÃO',
      _ => alertType,
    };
  }
}

// ── Quick Link Button (with race condition protection) ───
class _QuickLinkButton extends ConsumerStatefulWidget {
  final OperationalAlert alert;

  /// TASK 4: Full list of evidence IDs — passed to reconcileQuick
  final List<String> evidenceIds;

  const _QuickLinkButton({required this.alert, required this.evidenceIds});

  @override
  ConsumerState<_QuickLinkButton> createState() => _QuickLinkButtonState();
}

class _QuickLinkButtonState extends ConsumerState<_QuickLinkButton> {
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return AlertActionButton(
      label: _loading ? '' : 'Vincular',
      icon: _loading ? null : Icons.link_rounded,
      loading: _loading,
      color: VeraProbColors.primary,
      onPressed: _loading ? null : _onQuickLink,
      error: _error,
    );
  }

  Future<void> _onQuickLink() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final orgId = ref.read(currentOrganizationIdProvider);
      final userId = ref.read(currentOperatorIdProvider);
      if (orgId == null || userId == null) return;

      // TASK 4: Pass full evidenceIds list; for TELEGRAM_ORPHAN alerts
      // driver_id is resolved via context (populated by webhook at ingest time).
      await ref
          .read(quickReconciliationServiceProvider)
          .reconcileQuick(
            alertId: widget.alert.id,
            organizationId: orgId,
            userId: userId,
            evidenceIds: widget.evidenceIds,
          );
      // Stream will auto-remove the resolved alert
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Falha');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }
}

// ── Evidence Peek Widget ─────────────────────────────────
/// TASK 1: Shows up to 3 evidence thumbnails (48×48).
///
/// If more than 3 exist, the last thumb gets a "+N" overlay.
/// Tapping any thumb opens [EvidenceDossierModal] (full grid, 15 items).
/// All images are fetched exclusively via secure-evidence-proxy (INV-26).
class _EvidencePeekWidget extends ConsumerWidget {
  final List<String> evidenceIds;

  static const _kMaxThumbs = 3;
  static const _kSize = 48.0;

  const _EvidencePeekWidget({required this.evidenceIds});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (evidenceIds.isEmpty) return const SizedBox.shrink();

    final accessToken = ref.watch(currentSessionIdProvider) ?? '';
    final visible = evidenceIds.take(_kMaxThumbs).toList();
    final overflow = evidenceIds.length - _kMaxThumbs;

    return GestureDetector(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => EvidenceDossierModal(evidenceIds: evidenceIds),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < visible.length; i++) ...[
            _buildThumb(
              ref: ref,
              id: visible[i],
              accessToken: accessToken,
              // Last thumb gets overflow badge when there are more than 3
              overflowCount: (i == visible.length - 1 && overflow > 0)
                  ? overflow
                  : 0,
            ),
            if (i < visible.length - 1) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }

  Widget _buildThumb({
    required WidgetRef ref,
    required String id,
    required String accessToken,
    required int overflowCount,
  }) {
    // INV-26: images MUST flow through secure-evidence-proxy only
    final url = ref.read(evidenceUrlServiceProvider).getProxyUrl(id);

    final thumb = ClipRRect(
      borderRadius: VeraProbRadii.mdAll,
      child: CachedNetworkImage(
        imageUrl: url,
        httpHeaders: {'Authorization': 'Bearer $accessToken'},
        width: _kSize,
        height: _kSize,
        fit: BoxFit.cover,
        placeholder: (ctx, _) => _placeholder(),
        errorWidget: (ctx, _, _) => _placeholder(),
      ),
    );

    if (overflowCount <= 0) return thumb;

    // Last visible thumb: overlay with "+N" badge
    return Stack(
      clipBehavior: Clip.none,
      children: [
        thumb,
        Positioned(
          top: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: VeraProbColors.background.withValues(alpha: 0.85),
              borderRadius: VeraProbRadii.smAll,
            ),
            child: Text(
              '+$overflowCount',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: VeraProbColors.textPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget _placeholder() => Container(
    width: _kSize,
    height: _kSize,
    decoration: const BoxDecoration(
      color: VeraProbColors.surfaceElevated,
      borderRadius: VeraProbRadii.mdAll,
    ),
    child: const Icon(
      Icons.fingerprint_rounded,
      size: 20,
      color: VeraProbColors.textDisabled,
    ),
  );
}
