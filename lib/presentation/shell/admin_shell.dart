import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/features/admin/presentation/screens/admin_hub_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/alerts_triade_drawer.dart';

/// Navigation destinations for the admin icon sidebar.
///
/// 9.8.B: Consolidated from 8 → 6 items by merging `settings`, `userManagement`,
/// and `orgSettings` into a single `adminHub` destination with 3 tabs.
enum AdminDestination {
  commandCenter(
    icon: Icons.radar_outlined,
    selectedIcon: Icons.radar,
    label: 'Controle',
    tooltip: 'Centro de Controle',
    minimumRole: UserRole.auditor,
  ),
  trips(
    icon: Icons.timeline_outlined,
    selectedIcon: Icons.timeline,
    label: 'Viagens',
    tooltip: 'Timeline de Viagens',
    minimumRole: UserRole.auditor,
  ),
  resources(
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
    label: 'Recursos',
    tooltip: 'Motoristas, Veículos, Rotas',
    minimumRole: UserRole.operator,
  ),
  system(
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart,
    label: 'Sistema',
    tooltip: 'Saúde do Sistema',
    minimumRole: UserRole.admin,
  ),
  audit(
    icon: Icons.history_outlined,
    selectedIcon: Icons.history,
    label: 'Auditoria',
    tooltip: 'Auditoria OCC',
    minimumRole: UserRole.auditor,
  ),
  adminHub(
    icon: Icons.settings_applications_outlined,
    selectedIcon: Icons.settings_applications,
    label: 'Hub',
    tooltip: 'Central Administrativa',
    minimumRole: UserRole.operator,
  );

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final String tooltip;
  final UserRole minimumRole;

  const AdminDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.tooltip,
    required this.minimumRole,
  });
}

class AdminShell extends ConsumerStatefulWidget {
  /// Optional override child. When null, [_buildScreen] handles routing.
  final Widget? child;

  const AdminShell({super.key, this.child});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  AdminDestination currentDestination = AdminDestination.commandCenter;

  void onDestinationSelected(AdminDestination destination) {
    setState(() {
      currentDestination = destination;
    });
  }

  Widget _buildScreen(AdminDestination destination) {
    if (destination == AdminDestination.adminHub) {
      return const AdminHubScreen();
    }
    return widget.child ?? const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final isDrawerOpen = ref.watch(isAlertsDrawerOpenProvider);

    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: Row(
        children: [
          _AdminSidebar(
            currentDestination: currentDestination,
            onDestinationSelected: onDestinationSelected,
          ),
          Expanded(
            child: Column(
              children: [
                // ── Top Header ──
                _AdminHeader(
                  title: currentDestination.label,
                  onToggleAlerts: () {
                    ref
                        .read(isAlertsDrawerOpenProvider.notifier)
                        .set(!isDrawerOpen);
                  },
                ),
                // ── Main Content Area ──
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.03),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _buildScreen(currentDestination),
                  ),
                ),
              ],
            ),
          ),
          if (isDrawerOpen) const AlertsTriadeDrawer(),
        ],
      ),
    );
  }
}

class _AdminHeader extends StatelessWidget {
  final String title;
  final VoidCallback onToggleAlerts;

  const _AdminHeader({required this.title, required this.onToggleAlerts});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppTheme.surfaceColor,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: onToggleAlerts,
            icon: const Icon(Icons.notifications_outlined, size: 24),
            color: AppTheme.surfaceColor.withValues(alpha: 0.6),
            tooltip: 'Alertas Operacionais',
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.primaryColor,
            child: const Icon(Icons.person, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }
}

class _AdminSidebar extends ConsumerWidget {
  final AdminDestination currentDestination;
  final ValueChanged<AdminDestination> onDestinationSelected;

  const _AdminSidebar({
    required this.currentDestination,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userRole = ref.watch(currentUserRoleProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: 80,
          decoration: BoxDecoration(
            color: AppTheme.surfaceColor,
            border: Border(
              right: BorderSide(
                color: Colors.black.withValues(alpha: 0.05),
                width: 1,
              ),
            ),
          ),
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Column(
                    children: [
                      // Organization Logo (Navegável)
                      InkWell(
                        onTap: () => onDestinationSelected(
                          AdminDestination.commandCenter,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            gradient: AppTheme.primaryGradient,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.primaryColor.withValues(
                                  alpha: 0.3,
                                ),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'PF',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Navigation icons
                      ...AdminDestination.values
                          .where((dest) {
                            return userRole.hasPermission(dest.minimumRole);
                          })
                          .map((dest) {
                            final isSelected = dest == currentDestination;
                            return _SidebarIcon(
                              icon: isSelected ? dest.selectedIcon : dest.icon,
                              tooltip: dest.tooltip,
                              isSelected: isSelected,
                              onTap: () => onDestinationSelected(dest),
                            );
                          }),

                      const Spacer(),

                      // Profile / Logout
                      _SidebarIcon(
                        icon: Icons.account_circle_outlined,
                        tooltip: 'Meu Perfil',
                        onTap: () {},
                      ),
                      const SizedBox(height: 8),
                      _SidebarIcon(
                        icon: Icons.logout_rounded,
                        tooltip: 'Sair',
                        onTap: () {},
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SidebarIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarIcon({
    required this.icon,
    required this.tooltip,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.primaryColor.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              icon,
              color: isSelected ? AppTheme.primaryColor : Colors.black45,
              size: 26,
            ),
          ),
        ),
      ),
    );
  }
}
