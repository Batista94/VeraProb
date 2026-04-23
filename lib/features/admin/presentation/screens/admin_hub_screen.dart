import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/screens/evidence_reconciliation_screen.dart';
import 'package:veraprob/presentation/shell/settings_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'org_settings_screen.dart';
import 'user_management_screen.dart';

/// Central admin hub consolidating Settings, User Management, Org Settings,
/// and Evidence Reconciliation into a single TabBar destination.
///
/// WS-4: "Evidências" tab visible only to AUDITOR and TENANT_ADMIN (RBAC).
class AdminHubScreen extends ConsumerStatefulWidget {
  const AdminHubScreen({super.key});

  @override
  ConsumerState<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends ConsumerState<AdminHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late List<_TabDef> _visibleTabs;

  @override
  void initState() {
    super.initState();
    _visibleTabs = _buildVisibleTabs(ref.read(currentUserRoleProvider));
    _tabController = TabController(length: _visibleTabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<_TabDef> _buildVisibleTabs(UserRole role) {
    final tabs = <_TabDef>[
      const _TabDef(label: 'Ajustes', screen: SettingsScreen()),
      const _TabDef(label: 'Equipe', screen: UserManagementScreen()),
      const _TabDef(label: 'Organização', screen: OrgSettingsScreen()),
    ];
    // WS-4: Evidências tab — AUDITOR and ADMIN only
    if (role.hasPermission(UserRole.auditor)) {
      tabs.add(
        const _TabDef(
          label: 'Evidências',
          screen: EvidenceReconciliationScreen(),
        ),
      );
    }
    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: VeraProbColors.border)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: VeraProbColors.primary,
              unselectedLabelColor: VeraProbColors.textSecondary,
              indicatorColor: VeraProbColors.primary,
              tabs: _visibleTabs.map((t) => Tab(text: t.label)).toList(),
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: _visibleTabs.map((t) => t.screen).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabDef {
  final String label;
  final Widget screen;

  const _TabDef({required this.label, required this.screen});
}
