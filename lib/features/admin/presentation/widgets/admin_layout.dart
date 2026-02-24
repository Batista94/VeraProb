import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_navigation_provider.dart';
import '../../../../application/projections/providers/feed_health_projection_provider.dart';
import '../../../../dev/performance_metrics.dart';
import '../../../../state/providers/fleet_providers.dart';

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
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('🚌', style: TextStyle(fontSize: 20)),
            ),
            const SizedBox(width: 12),
            const Text(
              'BusFlow Admin',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
            ),
            const Spacer(),
            const _FeedHealthBadge(),
            const SizedBox(width: 16),
          ],
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Row(
            children: [
              // Sidebar (NavigationRail) for wide screens
              if (isWideScreen)
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    border: Border(
                      right: BorderSide(color: Colors.grey.shade200),
                    ),
                  ),
                  child: NavigationRail(
                    backgroundColor: Colors.transparent,
                    selectedIndex: selectedIndex,
                    onDestinationSelected: (index) {
                      ref.read(adminIndexProvider.notifier).state = index;
                    },
                    labelType: NavigationRailLabelType.all,
                    indicatorColor: colorScheme.primaryContainer,
                    selectedLabelTextStyle: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    unselectedLabelTextStyle: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                    useIndicator: true,
                    minWidth: 80,
                    destinations: destinations,
                  ),
                ),

              // Main Content
              Expanded(
                child: Container(
                  color: const Color(0xFFF5F7FA),
                  child: IndexedStack(index: selectedIndex, children: children),
                ),
              ),
            ],
          ),
          if (ref.watch(stressScenarioProvider) != null)
            const PerformanceOverlayHud(),
        ],
      ),
      // Bottom Navigation Bar for small screens
      bottomNavigationBar: isWideScreen
          ? null
          : BottomNavigationBar(
              currentIndex: selectedIndex,
              onTap: (index) {
                ref.read(adminIndexProvider.notifier).state = index;
              },
              selectedItemColor: colorScheme.primary,
              items: destinations.map((d) {
                return BottomNavigationBarItem(
                  icon: d.icon,
                  label: (d.label as Text).data,
                );
              }).toList(),
            ),
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
        color: health.color.withValues(alpha: 0.15),
        border: Border.all(color: health.color.withValues(alpha: 0.5)),
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
              boxShadow: [
                BoxShadow(
                  color: health.color.withValues(alpha: 0.5),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            health.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: health.color,
            ),
          ),
        ],
      ),
    );
  }
}
