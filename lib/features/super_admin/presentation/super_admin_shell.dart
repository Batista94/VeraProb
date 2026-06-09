import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/super_admin/proxy_resilience_notifier.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'widgets/contingency_banner.dart';
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
              NavigationRail(
                backgroundColor: VeraProbColors.superAdminSurface,
                selectedIndex: navigationShell.currentIndex,
                onDestinationSelected: navigationShell.goBranch,
                labelType: NavigationRailLabelType.all,
                selectedIconTheme: const IconThemeData(color: Colors.white),
                unselectedIconTheme: const IconThemeData(color: Colors.white54),
                selectedLabelTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                unselectedLabelTextStyle: const TextStyle(
                  color: Colors.white54,
                ),
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Column(
                    children: [
                      const Icon(Icons.shield, color: Colors.white, size: 32),
                      const SizedBox(height: 4),
                      Text(
                        'SuperAdmin',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                trailing: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white54),
                    tooltip: 'Sair',
                    onPressed: () async {
                      // INV-22: Reset resilience state before logout
                      ref.read(proxyResilienceProvider.notifier).reset();
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
              Expanded(
                child: Column(
                  children: [
                    const ContingencyBanner(),
                    Expanded(child: navigationShell),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
