import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/command_center/logic/alert_grouping.dart';
import 'package:veraprob/features/admin/presentation/command_center/models/driver_alert_group.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade/rich_evidence_card.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/sla_providers.dart';

export 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade/alerts_drawer_state.dart'
    show isAlertsDrawerOpenProvider;

/// Proactive Command Center drawer for operational alert triaging.
///
/// Features: smart grouping by driver, rich evidence cards, real-time sync
/// via StreamProvider, industrial sound for CRITICAL, collision awareness.
/// Cards live in `alerts_triade/` (P5c split).
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

  void _onAlertsChanged(
    AsyncValue<List<OperationalAlert>>? prev,
    AsyncValue<List<OperationalAlert>> next,
  ) {
    final prevIds =
        prev?.value
            ?.where((a) => a.severity == 'CRITICAL')
            .map((a) => a.id)
            .toSet() ??
        {};
    final nextCritical =
        next.value?.where((a) => a.severity == 'CRITICAL') ?? [];
    if (nextCritical.any((a) => !prevIds.contains(a.id))) {
      ref.read(alertSoundServiceProvider).playAlertPing();
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(activeAlertsStreamProvider);

    // Sound trigger: listen for new CRITICAL alerts
    ref.listen<AsyncValue<List<OperationalAlert>>>(
      activeAlertsStreamProvider,
      _onAlertsChanged,
    );

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
              AsyncError() =>
                alertsAsync.hasValue && alertsAsync.value != null
                    ? _GroupedAlertsList(alerts: alertsAsync.value!)
                    : Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Não foi possível carregar os alertas.',
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
          borderRadius: VeraProbRadii.mdAll,
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
                    topLeft: Radius.circular(VeraProbRadii.md),
                    bottomLeft: Radius.circular(VeraProbRadii.md),
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
                        right: Radius.circular(VeraProbRadii.md),
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
                                        'Motorista Não Identificado',
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
                                  borderRadius: VeraProbRadii.lgAll,
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
                        (alert) => RichEvidenceCard(alert: alert),
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
          borderRadius: VeraProbRadii.mdAll,
          border: Border.all(color: VeraProbColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              decoration: const BoxDecoration(
                color: VeraProbColors.border,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(VeraProbRadii.md),
                  bottomLeft: Radius.circular(VeraProbRadii.md),
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
                        borderRadius: VeraProbRadii.smAll,
                      ),
                    ),
                    Container(
                      width: 140,
                      height: 12,
                      decoration: BoxDecoration(
                        color: VeraProbColors.surfaceElevated,
                        borderRadius: VeraProbRadii.smAll,
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
