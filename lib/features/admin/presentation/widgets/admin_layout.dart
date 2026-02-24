import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/admin_navigation_provider.dart';

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
          ],
        ),
        backgroundColor: const Color(0xFF1A237E),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Row(
        children: [
          // Sidebar (NavigationRail) for wide screens
          if (isWideScreen)
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(right: BorderSide(color: Colors.grey.shade200)),
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
