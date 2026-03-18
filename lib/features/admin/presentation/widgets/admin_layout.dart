import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../providers/admin_navigation_provider.dart';
import '../../../../application/projections/providers/feed_health_projection_provider.dart';
import '../../../../dev/performance_metrics.dart';
import '../../../../state/providers/fleet_providers.dart';
import '../../../../application/adapters/stress_scenario_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../lock_screen.dart';

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
      backgroundColor: PactaFlowColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    PactaFlowColors.primary,
                    PactaFlowColors.primary.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: PactaFlowColors.primary.withValues(alpha: 0.2),
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
                'OCC • PactaFlow',
                style: PactaFlowTypography.sectionTitle.copyWith(
                  fontSize: 16,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w800,
                  color: PactaFlowColors.textPrimary,
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
        backgroundColor: PactaFlowColors.surface,
        foregroundColor: PactaFlowColors.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: PactaFlowColors.border, width: 0.5),
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
                  color: PactaFlowColors.background,
                  border: Border(
                    right: BorderSide(color: PactaFlowColors.border),
                  ),
                ),
                child: NavigationRail(
                  extended: isWideScreen,
                  minWidth: 72,
                  minExtendedWidth: 220,
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (index) {
                    ref.read(adminIndexProvider.notifier).state = index;
                  },
                  useIndicator: true,
                  destinations: destinations,
                ),
              ),
              Expanded(
                child: Container(
                  color: PactaFlowColors.background,
                  child: IndexedStack(
                    index: selectedIndex,
                    children: children
                        .map((child) => _AnimatedPage(child: child))
                        .toList(),
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
            ? PactaFlowColors.primary
            : PactaFlowColors.textDisabled,
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

class _LogoutButton extends StatelessWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout_rounded),
      tooltip: 'Sair',
      color: PactaFlowColors.textDisabled,
      onPressed: () async {
        await Supabase.instance.client.auth.signOut();
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
            style: PactaFlowTypography.badge.copyWith(
              color: health.color,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}
