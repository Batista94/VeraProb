import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/enums/user_role.dart';
import '../../../state/providers/auth_providers.dart';

/// Navigation destinations for the admin icon sidebar.
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
  settings(
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings,
    label: 'Ajustes',
    tooltip: 'Configurações do Sistema',
    minimumRole: UserRole.operator,
  ),
  userManagement(
    icon: Icons.people_outline,
    selectedIcon: Icons.people,
    label: 'Equipe',
    tooltip: 'Gestão de Usuários',
    minimumRole: UserRole.admin,
  ),
  orgSettings(
    icon: Icons.business_outlined,
    selectedIcon: Icons.business,
    label: 'Organização',
    tooltip: 'Configurações da Empresa',
    minimumRole: UserRole.admin,
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
  final Widget child;

  const AdminShell({super.key, required this.child});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  AdminDestination currentDestination = AdminDestination.commandCenter;

  void onDestinationSelected(AdminDestination destination) {
    setState(() {
      currentDestination = destination;
    });
    // Navigation logic would go here (e.g., GoRouter)
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.surfaceColor,
      body: Row(
        children: [
          _AdminSidebar(
            currentDestination: currentDestination,
            onDestinationSelected: onDestinationSelected,
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
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
              child: widget.child,
            ),
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

    return Container(
      width: 80,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceColor,
        border: Border(
          right: BorderSide(color: Colors.black.withValues(alpha: 0.05), width: 1),
        ),
      ),
      child: Column(
        children: [
          // Organization Logo or Initials
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.3),
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
          const SizedBox(height: 32),

          // Navigation icons
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
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
                ],
              ),
            ),
          ),

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
