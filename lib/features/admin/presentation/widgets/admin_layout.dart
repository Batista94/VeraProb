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

    return Scaffold(
      appBar: AppBar(
        title: const Text('BusFlow Admin 🚌'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          // Sidebar (NavigationRail) for wide screens
          if (isWideScreen)
            NavigationRail(
              backgroundColor: Colors.grey[100],
              selectedIndex: selectedIndex,
              onDestinationSelected: (index) {
                ref.read(adminIndexProvider.notifier).state = index;
              },
              labelType: NavigationRailLabelType.all,
              destinations: destinations,
            ),

          // Main Content
          Expanded(
            child: IndexedStack(index: selectedIndex, children: children),
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
