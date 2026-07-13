import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/app/routing/route_permissions.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/permissions_sync.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/application/projections/providers/feed_health_projection_provider.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade_drawer.dart';
import 'package:veraprob/features/admin/presentation/widgets/admin_session_keep_alive.dart';
import 'package:veraprob/features/admin/providers/vehicles_provider.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/justification_providers.dart';

/// Scaffold handle for imperative drawer control (incident-responsive
/// command center: auto-open on escalation, auto-close when the queue clears).
final _adminScaffoldKey = GlobalKey<ScaffoldState>();

/// Admin shell — the URL-addressable container for the 18 admin destinations.
///
/// Fed by the router's [StatefulShellRoute.indexedStack]: branch identity
/// (`navigationShell.currentIndex`) equals the `AdminNav` index, so the
/// sidebar, hub launcher, onboarding banner and command-center drawer stay in
/// sync against a single source of truth (the URL).
class AdminLayout extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const AdminLayout({super.key, required this.navigationShell});

  /// Switches to the branch at [index] (an `AdminNav` index) and clears any
  /// open contract detail so the destination opens at its list root.
  void _goBranch(WidgetRef ref, int index) {
    navigationShell.goBranch(index);
    ref.read(selectedContractIdProvider.notifier).set(null);
  }

  /// Sidebar pillar indices (real `AdminNav` indices, in order) the current
  /// session may see. A pillar whose route carries a fine-grained permission
  /// (`route_permissions`) is dropped when the claim is absent — the router
  /// guard already blocks direct navigation; this removes the dead entry point
  /// too (Pilar 3). `adminHub` is ungated, so the collapse target for deep hub
  /// screens is always present.
  List<int> _visiblePillars(WidgetRef ref) {
    final service = ref.watch(permissionServiceProvider);
    final visible = <int>[];
    for (var i = 0; i < pillarCount; i++) {
      final required = requiredPermissionFor(AdminNav.values[i].path);
      if (required == null || service.hasPermission(required)) {
        visible.add(i);
      }
    }
    return visible;
  }

  /// The 6 operational pillars rendered in the sidebar rail. Badges are live
  /// (pending sanctions / justifications) so the rail doubles as a triage cue.
  List<NavigationRailDestination> _buildDestinations(WidgetRef ref) {
    final pendingCount = ref.watch(pendingSanctionsCountProvider);
    final pendingJustificationCount = ref.watch(
      pendingJustificationsCountProvider,
    );

    return [
      const NavigationRailDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: Text('Painel de Controle'),
      ),
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount'),
          child: const Icon(Icons.approval_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount'),
          child: const Icon(Icons.approval),
        ),
        label: const Text('Fila Auditora'),
      ),
      NavigationRailDestination(
        icon: Badge(
          isLabelVisible: pendingJustificationCount > 0,
          label: Text('$pendingJustificationCount'),
          child: const Icon(Icons.shield_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: pendingJustificationCount > 0,
          label: Text('$pendingJustificationCount'),
          child: const Icon(Icons.shield),
        ),
        label: const Text('Portal Defesa'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.account_balance_outlined),
        selectedIcon: Icon(Icons.account_balance),
        label: Text('Visão Executiva'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
        label: Text('Log Operacional'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.admin_panel_settings_outlined),
        selectedIcon: Icon(Icons.admin_panel_settings),
        label: Text('Administração'),
      ),
    ];
  }

  List<NavigationDestination> _buildBottomDestinations(WidgetRef ref) {
    final pendingCount = ref.watch(pendingSanctionsCountProvider);
    final pendingJustificationCount = ref.watch(
      pendingJustificationsCountProvider,
    );

    return [
      const NavigationDestination(
        icon: Icon(Icons.dashboard_outlined),
        selectedIcon: Icon(Icons.dashboard),
        label: 'Painel',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount'),
          child: const Icon(Icons.approval_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: pendingCount > 0,
          label: Text('$pendingCount'),
          child: const Icon(Icons.approval),
        ),
        label: 'Fila',
      ),
      NavigationDestination(
        icon: Badge(
          isLabelVisible: pendingJustificationCount > 0,
          label: Text('$pendingJustificationCount'),
          child: const Icon(Icons.shield_outlined),
        ),
        selectedIcon: Badge(
          isLabelVisible: pendingJustificationCount > 0,
          label: Text('$pendingJustificationCount'),
          child: const Icon(Icons.shield),
        ),
        label: 'Defesa',
      ),
      const NavigationDestination(
        icon: Icon(Icons.account_balance_outlined),
        selectedIcon: Icon(Icons.account_balance),
        label: 'Executivo',
      ),
      const NavigationDestination(
        icon: Icon(Icons.history_outlined),
        selectedIcon: Icon(Icons.history),
        label: 'Log',
      ),
      const NavigationDestination(
        icon: Icon(Icons.admin_panel_settings_outlined),
        selectedIcon: Icon(Icons.admin_panel_settings),
        label: 'Admin',
      ),
    ];
  }

  PreferredSizeWidget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    bool isWideScreen,
  ) {
    return AppBar(
      automaticallyImplyLeading: false,
      actions: const [SizedBox.shrink()],
      title: Row(
        children: [
          // ── Logo Home-Anchor ──────────────────────────
          InkWell(
            borderRadius: VeraProbRadii.mdAll,
            onTap: () => _goBranch(ref, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        VeraProbColors.primary,
                        VeraProbColors.primary.withValues(alpha: 0.7),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: VeraProbRadii.mdAll,
                    boxShadow: [
                      BoxShadow(
                        color: VeraProbColors.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  // ACCENT-FILL-CONTRAST: foreground on primary fill is
                  // always the dark background token, never white.
                  child: const Icon(
                    Icons.hub_rounded,
                    color: VeraProbColors.background,
                    size: 20,
                  ),
                ),
                if (isWideScreen) ...[
                  const SizedBox(width: 16),
                  Text(
                    'OCC • veraprob',
                    style: VeraProbTypography.sectionTitle.copyWith(
                      fontSize: 16,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w800,
                      color: VeraProbColors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          if (isWideScreen) ...[
            const SizedBox(width: 16),
            const _FeedHealthBadge(),
          ],
          const SizedBox(width: 8),
          _OnboardingBadge(onNavigate: () => _goBranch(ref, 0)),
          const SizedBox(width: 8),
          const _AlertsButton(),
          const SizedBox(width: 8),
          const _LogoutButton(),
          const SizedBox(width: 8),
        ],
      ),
      backgroundColor: VeraProbColors.surface,
      foregroundColor: VeraProbColors.textPrimary,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: VeraProbColors.border, width: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar(
    BuildContext context,
    WidgetRef ref,
    bool isWideScreen,
    int selectedIndex,
    List<int> visiblePillars,
    List<NavigationRailDestination> destinations,
  ) {
    // Map the real branch index onto its position in the filtered rail. The
    // collapse target (adminHub) is always visible, so indexOf never fails.
    final railPos = visiblePillars.indexOf(railIndexFor(selectedIndex));
    return Container(
      decoration: const BoxDecoration(
        color: VeraProbColors.background,
        border: Border(right: BorderSide(color: VeraProbColors.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: NavigationRail(
                  extended: isWideScreen,
                  minWidth: 72,
                  minExtendedWidth: 220,
                  selectedIndex: railPos < 0 ? null : railPos,
                  onDestinationSelected: (railPos) {
                    final target = visiblePillars[railPos];
                    if (target == selectedIndex) return;
                    _goBranch(ref, target);
                  },
                  useIndicator: true,
                  destinations: destinations,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep fine-grained permission claims fresh while the tenant shell is
    // mounted (Pilar 2 §2.3): Realtime push + bounded current_perms_v() poll.
    ref.watch(permissionsSyncProvider);

    final selectedIndex = navigationShell.currentIndex;
    final visiblePillars = _visiblePillars(ref);
    final allRail = _buildDestinations(ref);
    final allBottom = _buildBottomDestinations(ref);
    final railDestinations = [for (final i in visiblePillars) allRail[i]];
    final bottomDestinations = [for (final i in visiblePillars) allBottom[i]];
    final bottomPos = visiblePillars.indexOf(railIndexFor(selectedIndex));
    final isCompact = VeraProbBreakpoints.isCompact(context);
    final isExpandedRail =
        MediaQuery.sizeOf(context).width >= VeraProbBreakpoints.medium;

    // ── Incident-responsive drawer ─────────────────────────────
    // Close the instant the queue empties so the operator never lands on the
    // useless "Operação Limpa" screen.
    ref.listen(activeAlertsStreamProvider, (prev, next) {
      final nextCount = next.value?.length ?? 0;
      final isOpen = ref.read(isAlertsDrawerOpenProvider);
      if (nextCount == 0 && isOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _adminScaffoldKey.currentState?.closeEndDrawer();
        });
      }
    });

    return AdminSessionKeepAlive(
      child: CallbackShortcuts(
        bindings: _pillarShortcuts(),
        child: Focus(
          autofocus: true,
          child: Scaffold(
            key: _adminScaffoldKey,
            backgroundColor: VeraProbColors.background,
            endDrawer: const AlertsTriadeDrawer(),
            onEndDrawerChanged: (isOpen) {
              ref.read(isAlertsDrawerOpenProvider.notifier).set(isOpen);
            },
            appBar: _buildAppBar(context, ref, !isCompact),
            bottomNavigationBar: isCompact
                ? NavigationBar(
                    backgroundColor: VeraProbColors.surfaceElevated,
                    indicatorColor: VeraProbColors.primary.withValues(
                      alpha: 0.15,
                    ),
                    // Deep hub branches (index >= pillarCount) collapse onto
                    // the Admin pillar; positions are filtered by permission,
                    // so remap through visiblePillars.
                    selectedIndex: bottomPos < 0 ? 0 : bottomPos,
                    onDestinationSelected: (pos) {
                      final target = visiblePillars[pos];
                      if (target == selectedIndex) return;
                      _goBranch(ref, target);
                    },
                    destinations: bottomDestinations,
                  )
                : null,
            body: Row(
              children: [
                if (!isCompact)
                  _buildSidebar(
                    context,
                    ref,
                    isExpandedRail,
                    selectedIndex,
                    visiblePillars,
                    railDestinations,
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: VeraProbBreakpoints.maxContent,
                      ),
                      child: ColoredBox(
                        color: VeraProbColors.background,
                        child: Column(
                          children: [
                            // Deep hub screen → offer a path back to the launcher.
                            if (selectedIndex > AdminNav.adminHub.index)
                              _HubBackButton(
                                onBack: () => navigationShell.goBranch(
                                  AdminNav.adminHub.index,
                                ),
                              ),
                            if (ref.watch(selectedContractIdProvider) != null)
                              _InternalBackButton(
                                onBack: () => ref
                                    .read(selectedContractIdProvider.notifier)
                                    .set(null),
                              ),
                            Expanded(child: navigationShell),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Ctrl/Cmd+1…6 jump straight to a sidebar pillar (Tier-1 OCC speed).
  Map<ShortcutActivator, VoidCallback> _pillarShortcuts() {
    void go(int index) => navigationShell.goBranch(index);
    const keys = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    return {
      for (var i = 0; i < pillarCount; i++) ...{
        SingleActivator(keys[i], control: true): () => go(i),
        SingleActivator(keys[i], meta: true): () => go(i),
      },
    };
  }
}

// ── Global Alert Entry-Point ──────────────────────────────
class _AlertsButton extends ConsumerWidget {
  const _AlertsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(activeAlertsStreamProvider);
    final count = alertsAsync.value?.length ?? 0;
    final hasAlerts = count > 0;

    return IconButton(
      icon: Badge(
        isLabelVisible: hasAlerts,
        backgroundColor: VeraProbColors.critical,
        label: Text(
          '$count',
          style: VeraProbTypography.badge.copyWith(
            color: VeraProbColors.background,
          ),
        ),
        child: const Icon(Icons.notifications_active_rounded),
      ),
      // Disambiguates from the onboarding badge: name + live count for
      // tooltip AND screen readers (IconButton derives semantics from it).
      tooltip: hasAlerts
          ? 'Triagem de Alertas — $count alerta${count > 1 ? 's' : ''} ativo${count > 1 ? 's' : ''}'
          : 'Sem alertas ativos',
      color: hasAlerts ? VeraProbColors.critical : VeraProbColors.textDisabled,
      onPressed: hasAlerts ? () => Scaffold.of(context).openEndDrawer() : null,
    );
  }
}

class _HubBackButton extends StatelessWidget {
  final VoidCallback onBack;
  const _HubBackButton({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        VeraProbSpacing.lg,
        VeraProbSpacing.sm,
        VeraProbSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('VOLTAR PARA ADMINISTRAÇÃO'),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.textSecondary,
              textStyle: VeraProbTypography.badge.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _InternalBackButton extends StatelessWidget {
  final VoidCallback onBack;
  const _InternalBackButton({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        VeraProbSpacing.lg,
        VeraProbSpacing.sm,
        VeraProbSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('VOLTAR PARA LISTA'),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.textSecondary,
              textStyle: VeraProbTypography.badge.copyWith(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutButton extends ConsumerWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.logout_rounded),
      tooltip: 'Sair',
      color: VeraProbColors.textDisabled,
      onPressed: () async {
        final router = GoRouter.of(context);
        await ref.read(authRepositoryProvider).signOut();
        router.go(AppRoutes.login);
      },
    );
  }
}

class _FeedHealthBadge extends ConsumerWidget {
  const _FeedHealthBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(feedHealthProjectionProvider);

    return Tooltip(
      message: 'Saúde da Ingestão de Telemetria — clique para detalhes',
      child: InkWell(
        borderRadius: VeraProbRadii.xlAll,
        onTap: () => context.go(AppRoutes.ingestionHealth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: health.color.withValues(alpha: 0.1),
            border: Border.all(color: health.color.withValues(alpha: 0.3)),
            borderRadius: VeraProbRadii.xlAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: health.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                health.label.toUpperCase(),
                style: VeraProbTypography.badge.copyWith(
                  color: health.color,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Discrete AppBar badge showing pending configuration prerequisites.
/// Renders [SizedBox.shrink] when all 4/4 are met. Taps navigate to Dashboard.
class _OnboardingBadge extends ConsumerWidget {
  final VoidCallback onNavigate;

  const _OnboardingBadge({required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesAsync = ref.watch(operationalZonesProvider);
    final contractorsAsync = ref.watch(contractorListProvider);
    final vehiclesAsync = ref.watch(vehiclesListProvider);
    final rulesAsync = ref.watch(slaTemplatesProvider);

    final hasZones = (zonesAsync.value ?? []).isNotEmpty;
    final hasContractors = (contractorsAsync.value ?? []).isNotEmpty;
    final hasVehicles = (vehiclesAsync.value ?? []).any(
      (v) =>
          v.status == VehicleStatus.available ||
          v.status == VehicleStatus.inService,
    );
    final hasRules = (rulesAsync.value ?? []).isNotEmpty;

    final completed = [
      hasZones,
      hasContractors,
      hasVehicles,
      hasRules,
    ].where((v) => v).length;
    final remaining = 4 - completed;

    if (remaining == 0) return const SizedBox.shrink();

    return Tooltip(
      message: 'Configuração pendente ($completed/4) — clique para completar',
      child: IconButton(
        icon: Badge(
          backgroundColor: VeraProbColors.warning,
          label: Text(
            '$remaining',
            style: VeraProbTypography.badge.copyWith(
              color: VeraProbColors.background,
            ),
          ),
          child: const Icon(Icons.checklist_rounded),
        ),
        color: VeraProbColors.warning,
        onPressed: () {
          ref.read(onboardingBannerVisibleProvider.notifier).toggle();
          onNavigate();
        },
      ),
    );
  }
}
