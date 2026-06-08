import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/application/projections/providers/feed_health_projection_provider.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/lock_screen.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade_drawer.dart';
import 'package:veraprob/features/admin/providers/vehicles_provider.dart';
import 'package:veraprob/state/providers/alert_providers.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';
import 'package:veraprob/state/providers/operational_zone_providers.dart';
import 'package:veraprob/state/providers/sla_template_providers.dart';

/// Scaffold handle for imperative drawer control (incident-responsive
/// command center: auto-open on escalation, auto-close when the queue clears).
final _adminScaffoldKey = GlobalKey<ScaffoldState>();

class AdminLayout extends ConsumerWidget {
  final List<Widget> children;
  final List<NavigationRailDestination> destinations;

  const AdminLayout({
    super.key,
    required this.children,
    required this.destinations,
  });

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
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              ref.read(adminIndexProvider.notifier).set(0);
              ref.read(selectedContractIdProvider.notifier).set(null);
            },
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
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: VeraProbColors.primary.withValues(alpha: 0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.hub_rounded,
                    color: Colors.white,
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
          _OnboardingBadge(
            onNavigate: () {
              ref.read(adminIndexProvider.notifier).set(0);
              ref.read(selectedContractIdProvider.notifier).set(null);
            },
          ),
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
  ) {
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
                  selectedIndex: railIndexFor(selectedIndex),
                  onDestinationSelected: (railIndex) {
                    if (railIndex == selectedIndex) return;
                    ref.read(adminIndexProvider.notifier).set(railIndex);
                    ref.read(selectedContractIdProvider.notifier).set(null);
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
    final selectedIndex = ref.watch(adminIndexProvider);
    final isWideScreen = MediaQuery.of(context).size.width >= 600;

    // ── Incident-responsive drawer ─────────────────────────────
    // Open on a new/escalating alert; close the instant the queue empties so
    // the operator never lands on the useless "Operação Limpa" screen.
    ref.listen(activeAlertsStreamProvider, (prev, next) {
      final prevCount = prev?.value?.length ?? 0;
      final nextCount = next.value?.length ?? 0;
      final isOpen = ref.read(isAlertsDrawerOpenProvider);
      if (nextCount == 0 && isOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _adminScaffoldKey.currentState?.closeEndDrawer();
        });
      } else if (nextCount > prevCount && !isOpen) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _adminScaffoldKey.currentState?.openEndDrawer();
        });
      }
    });

    return CallbackShortcuts(
      bindings: _pillarShortcuts(ref),
      child: Focus(
        autofocus: true,
        child: Scaffold(
          key: _adminScaffoldKey,
          backgroundColor: VeraProbColors.background,
          endDrawer: const AlertsTriadeDrawer(),
          onEndDrawerChanged: (isOpen) {
            ref.read(isAlertsDrawerOpenProvider.notifier).set(isOpen);
          },
          appBar: _buildAppBar(context, ref, isWideScreen),
          body: Row(
            children: [
              _buildSidebar(context, ref, isWideScreen, selectedIndex),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1600),
                    child: Container(
                      color: VeraProbColors.background,
                      child: Column(
                        children: [
                          // Deep hub screen → offer a path back to the launcher.
                          if (selectedIndex > AdminNav.adminHub.index)
                            _HubBackButton(
                              onBack: () => ref
                                  .read(adminIndexProvider.notifier)
                                  .set(AdminNav.adminHub.index),
                            ),
                          if (ref.watch(selectedContractIdProvider) != null)
                            _InternalBackButton(
                              onBack: () => ref
                                  .read(selectedContractIdProvider.notifier)
                                  .set(null),
                            ),
                          Expanded(
                            child: IndexedStack(
                              index: selectedIndex,
                              children: children,
                            ),
                          ),
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
    );
  }

  /// Ctrl/Cmd+1…6 jump straight to a sidebar pillar (Tier-1 OCC speed).
  Map<ShortcutActivator, VoidCallback> _pillarShortcuts(WidgetRef ref) {
    void go(int index) => ref.read(adminIndexProvider.notifier).set(index);
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
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        child: const Icon(Icons.notifications_active_rounded),
      ),
      tooltip: hasAlerts ? 'Triagem de Alertas' : 'Sem alertas ativos',
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('VOLTAR PARA ADMINISTRAÇÃO'),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.textSecondary,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
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
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('VOLTAR PARA LISTA'),
            style: TextButton.styleFrom(
              foregroundColor: VeraProbColors.textSecondary,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
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
        await ref.read(authRepositoryProvider).signOut();
        if (context.mounted) {
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute<void>(builder: (_) => const AdminLockScreen()),
            (_) => false,
          );
        }
      },
    );
  }
}

class _FeedHealthBadge extends ConsumerWidget {
  const _FeedHealthBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(feedHealthProjectionProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: health.color.withValues(alpha: 0.1),
        border: Border.all(color: health.color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(16),
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
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
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
