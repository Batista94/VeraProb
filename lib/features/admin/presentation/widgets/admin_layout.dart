import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/application/projections/providers/feed_health_projection_provider.dart';
import 'package:veraprob/dev/performance_metrics.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/application/adapters/stress_scenario_config.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/admin/presentation/lock_screen.dart';
import 'package:veraprob/presentation/shell/widgets/onboarding_progress_banner.dart';

class AdminLayout extends ConsumerWidget {
  final List<Widget> children;
  final List<NavigationRailDestination> destinations;

  const AdminLayout({
    super.key,
    required this.children,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(adminIndexProvider);
    final isWideScreen = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      backgroundColor: VeraProbColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
            const Spacer(),
            const _StressModeToggle(),
            if (isWideScreen) ...[
              const SizedBox(width: 16),
              const _FeedHealthBadge(),
            ],
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
      ),
      body: Stack(
        children: [
          Row(
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: VeraProbColors.background,
                  border: Border(
                    right: BorderSide(color: VeraProbColors.border),
                  ),
                ),
                child: NavigationRail(
                  extended: isWideScreen,
                  minWidth: 72,
                  minExtendedWidth: 220,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) {
                    if (index == selectedIndex) {
                      return; // stay on current screen
                    }
                    ref.read(adminIndexProvider.notifier).state = index;
                    ref.read(selectedContractIdProvider.notifier).state = null;
                  },
                  useIndicator: true,
                  destinations: destinations,
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1600),
                    child: Container(
                      color: VeraProbColors.background,
                      child: Column(
                        children: [
                          OnboardingProgressBanner(
                            // Translating destination labels to actual index in AdminHome
                            onNavigate: (destIdx) {
                              ref.read(adminIndexProvider.notifier).state =
                                  destIdx;
                              ref
                                      .read(selectedContractIdProvider.notifier)
                                      .state =
                                  null;
                            },
                          ),
                          if (ref.watch(selectedContractIdProvider) != null)
                            _InternalBackButton(
                              onBack: () =>
                                  ref
                                          .read(
                                            selectedContractIdProvider.notifier,
                                          )
                                          .state =
                                      null,
                            ),
                          Expanded(
                            child: IndexedStack(
                              index: selectedIndex,
                              children: children
                                  .map((child) => _AnimatedPage(child: child))
                                  .toList(),
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
          if (ref.watch(stressScenarioProvider) != null)
            const PerformanceOverlayHud(),
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

class _AnimatedPage extends StatelessWidget {
  final Widget child;
  const _AnimatedPage({required this.child});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: child,
    );
  }
}

class _StressModeToggle extends ConsumerWidget {
  const _StressModeToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStressMode = ref.watch(stressScenarioProvider) != null;
    return IconButton(
      icon: Icon(
        isStressMode ? Icons.speed_rounded : Icons.speed_outlined,
        color: isStressMode
            ? VeraProbColors.primary
            : VeraProbColors.textDisabled,
      ),
      tooltip: isStressMode ? 'Desativar Stress Mode' : 'Ativar Stress Mode',
      onPressed: () {
        if (isStressMode) {
          ref.read(stressScenarioProvider.notifier).state = null;
        } else {
          // Use a predefined scenario instead of a raw string
          ref.read(stressScenarioProvider.notifier).state =
              StressScenarioConfig.extreme250();
        }
      },
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
            MaterialPageRoute(builder: (_) => const AdminLockScreen()),
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
