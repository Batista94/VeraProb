import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../presentation/shell/settings_screen.dart';
import 'org_settings_screen.dart';
import 'user_management_screen.dart';

/// Central admin hub consolidating Settings, User Management, and Org Settings
/// into a single TabBar destination — reduces sidebar from 8 → 6 items (INV-18).
class AdminHubScreen extends ConsumerStatefulWidget {
  const AdminHubScreen({super.key});

  @override
  ConsumerState<AdminHubScreen> createState() => _AdminHubScreenState();
}

class _AdminHubScreenState extends ConsumerState<AdminHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = [
    Tab(text: 'Ajustes'),
    Tab(text: 'Equipe'),
    Tab(text: 'Organização'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              border: Border(
                bottom: BorderSide(color: VeraProbColors.border),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: VeraProbColors.primary,
              unselectedLabelColor: VeraProbColors.textSecondary,
              indicatorColor: VeraProbColors.primary,
              tabs: _tabs,
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                SettingsScreen(),
                UserManagementScreen(),
                OrgSettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
