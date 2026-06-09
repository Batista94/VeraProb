import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/features/super_admin/presentation/super_admin_shell.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';

/// Builds the guarded [SuperAdminShell] through a [StatefulShellRoute] with
/// placeholder branch bodies — the rail's destinations come from the shell, not
/// the branch screens.
GoRouter _superAdminRouter() {
  StatefulShellBranch branch(String path) => StatefulShellBranch(
    routes: [GoRoute(path: path, builder: (_, _) => const SizedBox.shrink())],
  );

  return GoRouter(
    initialLocation: AppRoutes.superAdminTenants,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            SuperAdminShell(navigationShell: navigationShell),
        branches: [
          branch(AppRoutes.superAdminTenants),
          branch(AppRoutes.superAdminNewOrg),
          branch(AppRoutes.superAdminAuditLog),
        ],
      ),
    ],
  );
}

void main() {
  Widget buildTestableWidget({
    required bool isSuperAdmin,
    required bool isAal2,
  }) {
    return ProviderScope(
      overrides: [
        isSuperAdminProvider.overrideWithValue(isSuperAdmin),
        isSuperAdminAal2Provider.overrideWithValue(isAal2),
        securityIncidentLoggerProvider.overrideWithValue(
          SecurityIncidentLogger(null),
        ),
        authStateProvider.overrideWith(
          (ref) => const Stream<AuthState>.empty(),
        ),
      ],
      child: MaterialApp.router(routerConfig: _superAdminRouter()),
    );
  }

  group('RBAC Visibility UI Test (CT35)', () {
    testWidgets('Happy Path: SuperAdmin sees governance menus', (tester) async {
      await tester.pumpWidget(
        buildTestableWidget(isSuperAdmin: true, isAal2: true),
      );
      await tester.pumpAndSettle();

      // NavigationRail should be rendered with its destinations
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Tenants'), findsOneWidget);
      expect(find.text('Nova Org'), findsOneWidget);
      expect(find.text('Audit Log'), findsOneWidget);
    });

    testWidgets('Adverse Path: Org_Admin does not see global governance menus', (
      tester,
    ) async {
      // isSuperAdmin = false should make the SuperAdminGuard render the NotFoundPage.
      await tester.pumpWidget(
        buildTestableWidget(isSuperAdmin: false, isAal2: true),
      );
      await tester.pumpAndSettle();

      // The NavigationRail and its menus should NOT be in the widget tree
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('Tenants'), findsNothing);
      expect(find.text('Nova Org'), findsNothing);
      expect(find.text('Audit Log'), findsNothing);
    });
  });
}
