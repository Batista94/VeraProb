import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'widgets/admin_layout.dart';

import 'dashboard_screen.dart';
import 'drivers_screen.dart';
import 'timecard_reports_screen.dart';
import 'command_center/screens/operational_audit_screen.dart';
import 'screens/contracts_screen.dart';
import 'screens/sla_audit_screen.dart';
import 'screens/sla_financial_impact_screen.dart';
import 'screens/operational_zones_screen.dart';
import 'screens/billing_cycle_reports_screen.dart';
import 'screens/org_settings_screen.dart';
import 'screens/user_management_screen.dart';
import 'screens/contractor_management_screen.dart';
import 'screens/auditor_queue_screen.dart';
import 'screens/defense_portal_screen.dart';
import 'screens/sla_template_library_screen.dart';
import '../../../state/providers/auditor_queue_providers.dart';
import '../../../state/providers/justification_providers.dart';

class AdminHome extends ConsumerWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(pendingSanctionsCountProvider);
    final pendingJustificationCount = ref.watch(
      pendingJustificationsCountProvider,
    );

    return AdminLayout(
      destinations: [
        const NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Visão Geral'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.people_outlined),
          selectedIcon: Icon(Icons.people),
          label: Text('Motoristas'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.access_time_outlined),
          selectedIcon: Icon(Icons.access_time_filled),
          label: Text('Ponto Eletrônico'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: Text('Auditoria OCC'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.description_outlined),
          selectedIcon: Icon(Icons.description),
          label: Text('Contratos'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.verified_user_outlined),
          selectedIcon: Icon(Icons.verified_user),
          label: Text('Auditoria de SLA'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.account_balance_outlined),
          selectedIcon: Icon(Icons.account_balance),
          label: Text('Impacto Financeiro'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.place_outlined),
          selectedIcon: Icon(Icons.place),
          label: Text('Zonas Operacionais'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.summarize_outlined),
          selectedIcon: Icon(Icons.summarize),
          label: Text('Relatórios'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.business_outlined),
          selectedIcon: Icon(Icons.business),
          label: Text('Organização'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.manage_accounts_outlined),
          selectedIcon: Icon(Icons.manage_accounts),
          label: Text('Usuários'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.handshake_outlined),
          selectedIcon: Icon(Icons.handshake),
          label: Text('Contratantes'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.library_books_outlined),
          selectedIcon: Icon(Icons.library_books),
          label: Text('Modelos SLA'),
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
      ],
      children: const [
        DashboardScreen(),
        DriversScreen(),
        TimecardReportsScreen(),
        OperationalAuditScreen(),
        ContractsScreen(),
        SlaAuditScreen(),
        SlaFinancialImpactScreen(),
        OperationalZonesScreen(),
        BillingCycleReportsScreen(),
        OrgSettingsScreen(),
        UserManagementScreen(),
        ContractorManagementScreen(),
        SlaTemplateLibraryScreen(),
        AuditorQueueScreen(),
        DefensePortalScreen(),
      ],
    );
  }
}
