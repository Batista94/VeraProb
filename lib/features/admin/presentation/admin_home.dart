import 'package:flutter/material.dart';
import 'widgets/admin_layout.dart';

import 'dashboard_screen.dart';
import 'drivers_screen.dart';
import 'timecard_reports_screen.dart';
import 'command_center/screens/operational_audit_screen.dart';
import 'screens/sla_audit_screen.dart';
import 'screens/sla_financial_impact_screen.dart';
import 'screens/billing_cycle_reports_screen.dart';

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
        NavigationRailDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: Text('Auditoria OCC'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.verified_user_outlined),
          selectedIcon: Icon(Icons.verified_user),
          label: Text('Auditoria de SLA'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.account_balance_outlined),
          selectedIcon: Icon(Icons.account_balance),
          label: Text('Impacto Financeiro'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.summarize_outlined),
          selectedIcon: Icon(Icons.summarize),
          label: Text('Relatórios'),
        ),
      ],
      children: [
        DashboardScreen(),
        DriversScreen(),
        TimecardReportsScreen(),
        OperationalAuditScreen(),
        SlaAuditScreen(),
        SlaFinancialImpactScreen(),
        BillingCycleReportsScreen(),
      ],
    );
  }
}
