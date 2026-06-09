import 'package:cached_network_image/cached_network_image.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/evidence_dossier_modal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/command_center/logic/alert_grouping.dart';
import 'package:veraprob/features/admin/presentation/command_center/models/driver_alert_group.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_category_chip.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_link_source_chip.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/state/providers/sla_providers.dart';
import 'package:veraprob/state/providers/shared_providers.dart';

/// State to control the visibility of the Alerts Triade Drawer.
class _IsAlertsDrawerOpenNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final isAlertsDrawerOpenProvider =
    NotifierProvider<_IsAlertsDrawerOpenNotifier, bool>(
      _IsAlertsDrawerOpenNotifier.new,
    );

/// Proactive Command Center drawer for operational alert triaging.
///
/// Features: smart grouping by driver, rich evidence cards, real-time sync
/// via StreamProvider, industrial sound for CRITICAL, collision awareness.
///
/// INV-1: Alerts are org-scoped via the provider chain.
/// INV-7: Strictly typed — no `dynamic`.
class AlertsTriadeDrawer extends ConsumerStatefulWidget {
  const AlertsTriadeDrawer({super.key});

  @override
  ConsumerState<AlertsTriadeDrawer> createState() => _AlertsTriadeDrawerState();
}

class _AlertsTriadeDrawerState extends ConsumerState<AlertsTriadeDrawer> {
  @override
  void initState() {
    super.initState();
    // Auto-mark alerts as viewed when drawer opens (fire-and-forget)
    WidgetsBinding.instance.addPostFrameCallback((_) => _markAllViewed());
  }

  void _markAllViewed() {
    final alerts = ref.read(activeAlertsStreamProvider).value;
    final userId = ref.read(currentOperatorIdProvider);
    if (alerts == null || alerts.isEmpty || userId == null) return;
    final repo = ref.read(operationalAlertRepositoryProvider);
    for (final alert in alerts) {
      if (!alert.viewedByUserIds.contains(userId)) {
        repo.markViewed(alert.id, userId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(activeAlertsStreamProvider);

    // Sound trigger: listen for new CRITICAL alerts
    ref.listen<AsyncValue<List<OperationalAlert>>>(activeAlertsStreamProvider, (
      prev,
      next,
    ) {
      final prevIds =
          prev?.value
              ?.where((a) => a.severity == 'CRITICAL')
              .map((a) => a.id)
              .toSet() ??
          {};
      final nextCritical =
          next.value?.where((a) => a.severity == 'CRITICAL') ?? [];
      final hasNew = nextCritical.any((a) => !prevIds.contains(a.id));
      if (hasNew) {
        ref.read(alertSoundServiceProvider).playAlertPing();
      }
    });

    return Container(
      width: (MediaQuery.sizeOf(context).width * 0.28).clamp(300.0, 400.0),
      decoration: const BoxDecoration(
        color: VeraProbColors.surface,
        border: Border(
          left: BorderSide(color: VeraProbColors.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DrawerHeader(onClose: () => Navigator.of(context).pop()),
          if (alertsAsync.isLoading)
            const LinearProgressIndicator(
              backgroundColor: VeraProbColors.background,
              color: VeraProbColors.primary,
              minHeight: 2,
            ),
          Expanded(
            child: switch (alertsAsync) {
              // Stale-while-revalidate (Req 5.5): During refresh with previous
              // data, AsyncValue stays as AsyncData in Riverpod v3.
              // AsyncLoading only matches on initial load (no previous data).
              AsyncLoading() =>
                alertsAsync.hasValue && alertsAsync.value != null
                    ? _GroupedAlertsList(alerts: alertsAsync.value!)
                    : const _LoadingPlaceholder(),
              AsyncError(:final error) =>
                alertsAsync.hasValue && alertsAsync.value != null
                    ? _GroupedAlertsList(alerts: alertsAsync.value!)
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Erro ao carregar alertas: $error',
                            style: VeraProbTypography.bodySmall.copyWith(
                              color: VeraProbColors.critical,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
              AsyncData(:final value) =>
                value.isEmpty
                    ? const _EmptyState()
                    : _GroupedAlertsList(alerts: value),
            },
          ),
        ],
      ),
    );
  }
}

// ── Header ───────────────────────────────────────────────
class _DrawerHeader extends StatelessWidget {
  final VoidCallback onClose;
  const _DrawerHeader({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: VeraProbColors.background,
        border: Border(
          bottom: BorderSide(color: VeraProbColors.border, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(
                Icons.crisis_alert_rounded,
                color: VeraProbColors.critical,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Centro de Comando',
                style: VeraProbTypography.sectionTitle.copyWith(
                  color: VeraProbColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(
              Icons.close,
              color: VeraProbColors.textSecondary,
              size: 20,
            ),
            onPressed: onClose,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            tooltip: 'Fechar',
          ),
        ],
      ),
    );
  }
}

// ── Grouped Alerts List ──────────────────────────────────
class _GroupedAlertsList extends ConsumerWidget {
  final List<OperationalAlert> alerts;
  const _GroupedAlertsList({required this.alerts});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = groupAlertsByDriver(alerts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Text(
                '${alerts.length} ALERTA${alerts.length > 1 ? 'S' : ''}',
                style: VeraProbTypography.badge.copyWith(
                  color: VeraProbColors.critical,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '• ${groups.length} motorista${groups.length > 1 ? 's' : ''}',
                style: VeraProbTypography.caption,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: groups.length,
            itemBuilder: (_, i) => _DriverGroupCard(group: groups[i]),
          ),
        ),
      ],
    );
  }
}

// ── Driver Group Card (Expandable) ───────────────────────
class _DriverGroupCard extends StatefulWidget {
  final DriverAlertGroup group;
  const _DriverGroupCard({required this.group});

  @override
  State<_DriverGroupCard> createState() => _DriverGroupCardState();
}

class _DriverGroupCardState extends State<_DriverGroupCard> {
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Auto-expand if only 1-2 alerts
    _expanded = widget.group.count <= 2;
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final healthColor = _healthColor(group.contractHealth);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: VeraProbColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VeraProbColors.border),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Severity Indicator ──
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: healthColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    bottomLeft: Radius.circular(8),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    // ── Group Header ──
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(
                              _healthIcon(group.contractHealth),
                              color: healthColor,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    group.driverName ??
                                        'Operador Não Identificado',
                                    style: VeraProbTypography.bodyMedium
                                        .copyWith(fontWeight: FontWeight.w600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (group.driverId != '_unknown')
                                    Text(
                                      group.driverId.length > 8
                                          ? '${group.driverId.substring(0, 8)}…'
                                          : group.driverId,
                                      style: VeraProbTypography.caption,
                                    ),
                                ],
                              ),
                            ),
                            if (group.count > 1)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: healthColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '+${group.count}',
                                  style: VeraProbTypography.badge.copyWith(
                                    color: healthColor,
                                  ),
                                ),
                              ),
                            const SizedBox(width: 4),
                            Icon(
                              _expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded,
                              color: VeraProbColors.textDisabled,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // ── Expanded Alert Cards ──
                    if (_expanded)
                      ...group.alerts.map(
                        (alert) => _RichEvidenceCard(alert: alert),
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

  static Color _healthColor(ContractHealthStatus status) {
    return switch (status) {
      ContractHealthStatus.critical => VeraProbColors.critical,
      ContractHealthStatus.yellow => VeraProbColors.delayed,
      ContractHealthStatus.green => VeraProbColors.onTime,
    };
  }

  static IconData _healthIcon(ContractHealthStatus status) {
    return switch (status) {
      ContractHealthStatus.critical => Icons.error_rounded,
      ContractHealthStatus.yellow => Icons.warning_amber_rounded,
      ContractHealthStatus.green => Icons.check_circle_rounded,
    };
  }
}

// ── Rich Evidence Card ───────────────────────────────────
class _RichEvidenceCard extends ConsumerWidget {
  final OperationalAlert alert;
  const _RichEvidenceCard({required this.alert});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final severityColor = _severityColor(alert.severity);
    final timeAgo = _formatTimeAgo(alert.triggeredAtUtc);
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
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: VeraProbColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: type + severity + time ──
          Row(
            children: [
              _SeverityBadge(
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
                _PhotoCountBadge(count: evidenceIds.length),
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
              Text(timeAgo, style: VeraProbTypography.caption),
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
                child: _ActionButton(
                  label: 'Reconciliar',
                  icon: Icons.open_in_new_rounded,
                  onPressed: () {
                    ref
                        .read(selectedContractIdProvider.notifier)
                        .set(alert.contractId);
                    Navigator.of(context).pop();
                    context.go(AdminNav.slaAudit.path);
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
      _ => alertType,
    };
  }

  static String _formatTimeAgo(DateTime utcTime) {
    final diff = DateTime.now().toUtc().difference(utcTime);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    return 'há ${diff.inDays}d';
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
    return _ActionButton(
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
    } catch (e) {
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

// ── Action Button ────────────────────────────────────────
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final Color? color;
  final String? error;

  const _ActionButton({
    required this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.color,
    this.error,
  });

  @override
  Widget build(BuildContext context) {
    final btnColor = error != null
        ? VeraProbColors.critical
        : (color ?? VeraProbColors.textSecondary);

    return SizedBox(
      height: 28,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: btnColor,
          side: BorderSide(color: btnColor.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: VeraProbTypography.badge,
        ),
        child: loading
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 12),
                    const SizedBox(width: 4),
                  ],
                  Text(error ?? label),
                ],
              ),
      ),
    );
  }
}

// ── Severity Badge ───────────────────────────────────────
class _SeverityBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _SeverityBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Photo Count Badge ────────────────────────────────────
class _PhotoCountBadge extends StatelessWidget {
  final int count;
  const _PhotoCountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    // "10 FOTOS" for exact 10, "+N FOTOS" for burst < 10
    final label = count >= 10 ? '$count FOTOS' : '+$count FOTOS';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: VeraProbColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: VeraProbColors.primary.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: VeraProbColors.primary,
          letterSpacing: 0.4,
        ),
      ),
    );
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
      borderRadius: BorderRadius.circular(8),
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
              borderRadius: BorderRadius.circular(4),
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
    decoration: BoxDecoration(
      color: VeraProbColors.surfaceElevated,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(
      Icons.fingerprint_rounded,
      size: 20,
      color: VeraProbColors.textDisabled,
    ),
  );
}

// ── Empty State ──────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            size: 48,
            color: VeraProbColors.onTime.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            'Operação Limpa',
            style: VeraProbTypography.sectionTitle.copyWith(
              color: VeraProbColors.onTime.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Nenhum alerta contratual pendente.',
            style: VeraProbTypography.bodySmall.copyWith(
              color: VeraProbColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loading Placeholder ──────────────────────────────────
class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(children: List.generate(3, (_) => const _SkeletonCard())),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: VeraProbColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: VeraProbColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              decoration: const BoxDecoration(
                color: VeraProbColors.border,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: VeraProbColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    Container(
                      width: 140,
                      height: 12,
                      decoration: BoxDecoration(
                        color: VeraProbColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
