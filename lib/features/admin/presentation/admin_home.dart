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
import 'screens/admin_hub_screen.dart';
import 'screens/evidence_reconciliation_screen.dart';
import 'package:veraprob/presentation/shell/settings_screen.dart';
import 'package:veraprob/state/providers/auditor_queue_providers.dart';
import 'package:veraprob/state/providers/justification_providers.dart';

/// Admin shell composition.
///
/// `children` order MUST stay aligned with the `AdminNav` enum
/// (`admin_navigation_provider.dart`) — index identity is the contract that
/// keeps the sidebar, hub launcher, onboarding banner and command-center
/// drawer in sync.
class AdminHome extends ConsumerWidget {
  const AdminHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingCount = ref.watch(pendingSanctionsCountProvider);
    final pendingJustificationCount = ref.watch(
      pendingJustificationsCountProvider,
    );

    return AdminLayout(
      // ── 6 operational pillars (rail destinations) ──────────
      destinations: [
        const NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Painel de Controle'),
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
        const NavigationRailDestination(
          icon: Icon(Icons.account_balance_outlined),
          selectedIcon: Icon(Icons.account_balance),
          label: Text('Impacto Financeiro'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.history_outlined),
          selectedIcon: Icon(Icons.history),
          label: Text('Auditoria OCC'),
        ),
        const NavigationRailDestination(
          icon: Icon(Icons.admin_panel_settings_outlined),
          selectedIcon: Icon(Icons.admin_panel_settings),
          label: Text('Administração'),
        ),
      ],
      // ── 18 screens (order == AdminNav) ─────────────────────
      children: const [
        DashboardScreen(), // 0  dashboard
        AuditorQueueScreen(), // 1  auditorQueue
        DefensePortalScreen(), // 2  defensePortal
        SlaFinancialImpactScreen(), // 3  financialImpact
        OperationalAuditScreen(), // 4  operationalAudit
        AdminHubScreen(), // 5  adminHub (launcher)
        DriversScreen(), // 6  drivers
        TimecardReportsScreen(), // 7  timecards
        ContractsScreen(), // 8  contracts
        SlaAuditScreen(), // 9  slaAudit
        OperationalZonesScreen(), // 10 zones
        BillingCycleReportsScreen(), // 11 billingReports
        SlaTemplateLibraryScreen(), // 12 slaTemplates
        OrgSettingsScreen(), // 13 orgSettings
        UserManagementScreen(), // 14 userManagement
        ContractorManagementScreen(), // 15 contractors
        SettingsScreen(), // 16 settings
        EvidenceReconciliationScreen(), // 17 evidence
      ],
    );
  }
}
