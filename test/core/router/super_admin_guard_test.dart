import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/features/super_admin/presentation/super_admin_shell.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/not_found_page.dart';
import 'package:veraprob/state/providers/super_admin_auth_providers.dart';
import 'package:veraprob/state/providers/security_incident_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Minimal router that builds the guarded [SuperAdminShell] via a
/// [StatefulShellRoute.indexedStack] with placeholder branch bodies (the real
/// branch screens pull heavy providers irrelevant to the guard's contract).
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

class _FakeSecurityIncidentLogger implements SecurityIncidentLogger {
  final List<Map<String, dynamic>> calls = [];
  @override
  Future<void> log({
    required String eventType,
    required Map<String, dynamic> metadata,
    required Map<String, dynamic> jwtClaimsSnapshot,
  }) async {
    calls.add({'event_type': eventType});
  }
}

void main() {
  Widget buildAppWithDeepLink({required bool isSuperAdmin}) {
    final fakeLogger = _FakeSecurityIncidentLogger();

    return ProviderScope(
      overrides: [
        isSuperAdminProvider.overrideWithValue(isSuperAdmin),
        isSuperAdminAal2Provider.overrideWithValue(true), // Skip MFA complexity
        securityIncidentLoggerProvider.overrideWithValue(fakeLogger),
        authStateProvider.overrideWith(
          (ref) => const Stream<AuthState>.empty(),
        ),
      ],
      // Simulating a deep link directly to the SuperAdmin portal.
      child: MaterialApp.router(routerConfig: _superAdminRouter()),
    );
  }

  group('SuperAdmin Guard Deep Link Test (CT33)', () {
    testWidgets(
      'Adverse Path: Org_Admin trying to access SuperAdmin routes is blocked',
      (tester) async {
        await tester.pumpWidget(buildAppWithDeepLink(isSuperAdmin: false));
        await tester.pumpAndSettle();

        // Guard should intercept and render NotFoundPage instead of the shell.
        // This proves INV-26 is respected.
        expect(find.byType(NotFoundPage), findsOneWidget);
        expect(find.byType(NavigationRail), findsNothing);
      },
    );

    testWidgets('Happy Path: SuperAdmin can access SuperAdmin routes', (
      tester,
    ) async {
      await tester.pumpWidget(buildAppWithDeepLink(isSuperAdmin: true));
      await tester.pumpAndSettle();

      // Should render normally
      expect(find.byType(NotFoundPage), findsNothing);
      expect(find.byType(NavigationRail), findsOneWidget);
    });
  });
}
