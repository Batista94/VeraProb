import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'widgets/super_admin_guard.dart';
import 'widgets/super_admin_session_timeout.dart';

/// Isolated shell for the SuperAdmin portal.
///
/// Navigation: indigo NavigationRail with 3 URL-addressable branches, fed by the
/// router's [StatefulShellRoute.indexedStack] (`navigationShell.currentIndex`
/// equals the branch order: Tenants / Nova Org / Audit Log). Wrapped in
/// [SuperAdminGuard] — access denied if JWT lacks `super_admin: true`.
class SuperAdminShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const SuperAdminShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SuperAdminSessionTimeout(
      child: SuperAdminGuard(
        child: Scaffold(
          body: Row(
            children: [
              // ── NavigationRail (indigo) ─────────────────────────────
              // Active styling inherited from navigationRailTheme (P3).
              // Unselected stays local: the theme's textDisabled was tuned
              // for `background` and fails 3:1 on superAdminSurface —
              // textSecondary passes (≈5.6:1) and keeps the rail legible.
              NavigationRail(
                backgroundColor: VeraProbColors.superAdminSurface,
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: navigationShell.goBranch,
                labelType: NavigationRailLabelType.all,
                unselectedIconTheme: const IconThemeData(
                  color: VeraProbColors.textSecondary,
                  size: 24,
                ),
                unselectedLabelTextStyle: VeraProbTypography.caption.copyWith(
                  fontSize: 13,
                  color: VeraProbColors.textSecondary,
                ),
                leading: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: VeraProbSpacing.md,
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.shield,
                        color: VeraProbColors.textPrimary,
                        size: 32,
                      ),
                      const SizedBox(height: VeraProbSpacing.xs),
                      Text(
                        'SuperAdmin',
                        style: VeraProbTypography.caption.copyWith(
                          color: VeraProbColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(bottom: VeraProbSpacing.md),
                  child: IconButton(
                    icon: const Icon(
                      Icons.logout,
                      color: VeraProbColors.textSecondary,
                    ),
                    tooltip: 'Sair',
                    onPressed: () async {
                      await ref.read(authRepositoryProvider).signOut();
                      if (context.mounted) {
                        context.go(AppRoutes.login);
                      }
                    },
                  ),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.business_outlined),
                    selectedIcon: Icon(Icons.business),
                    label: Text('Tenants'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.add_business_outlined),
                    selectedIcon: Icon(Icons.add_business),
                    label: Text('Nova Org'),
                  ),
                  NavigationRailDestination(
                    icon: Icon(Icons.manage_search_outlined),
                    selectedIcon: Icon(Icons.manage_search),
                    label: Text('Audit Log'),
                  ),
                ],
              ),
              const VerticalDivider(width: 1),
              // ── Main content ───────────────────────────────────────
              Expanded(child: navigationShell),
            ],
          ),
        ),
      ),
    );
  }
}
