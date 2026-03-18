import 'package:flutter/material.dart';
import 'package:pactaflow/features/admin/presentation/drivers_screen.dart';
import 'tabs/vehicles_tab.dart';
import 'tabs/routes_tab.dart';

class ResourceManagementScreen extends StatelessWidget {
  const ResourceManagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          // Tab bar
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: const TabBar(
              isScrollable: false,
              tabs: [
                Tab(icon: Icon(Icons.people_alt_outlined), text: 'Motoristas'),
                Tab(
                  icon: Icon(Icons.directions_bus_outlined),
                  text: 'Veículos',
                ),
                Tab(icon: Icon(Icons.route_outlined), text: 'Rotas'),
              ],
            ),
          ),
          // Tab content
          const Expanded(
            child: TabBarView(
              children: [DriversScreen(), VehiclesTab(), RoutesTab()],
            ),
          ),
        ],
      ),
    );
  }
}
