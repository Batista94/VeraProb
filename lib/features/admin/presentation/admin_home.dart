import 'package:flutter/material.dart';
import 'widgets/admin_layout.dart';

import 'dashboard_screen.dart';
import 'drivers_screen.dart';
import 'timecard_reports_screen.dart';

class AdminHome extends StatelessWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminLayout(
      destinations: [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Visão Geral'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.people_outlined),
          selectedIcon: Icon(Icons.people),
          label: Text('Motoristas'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.access_time_outlined),
          selectedIcon: Icon(Icons.access_time_filled),
          label: Text('Ponto Eletrônico'),
        ),
      ],
      children: [DashboardScreen(), DriversScreen(), TimecardReportsScreen()],
    );
  }
}
