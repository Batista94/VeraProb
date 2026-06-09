import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:veraprob/app/routing/app_routes.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/screens/admin_hub_screen.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/features/admin/providers/onboarding_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

/// Router mirroring the admin shell branch paths: the hub renders
/// [AdminHubScreen]; every other [AdminNav] path renders a sentinel so a card
/// tap (`context.go(item.destination.path)`) drives a real location change we
/// can assert against — replacing the removed `adminIndexProvider`.
GoRouter _hubRouter() {
  return GoRouter(
    initialLocation: AdminNav.adminHub.path,
    routes: [
      for (final nav in AdminNav.values)
        GoRoute(
          path: nav.path,
          builder: (context, state) => Scaffold(
            body: nav == AdminNav.adminHub
                ? const AdminHubScreen()
                : Text('route:${nav.name}'),
          ),
        ),
    ],
  );
}

Widget _buildHub(ProviderContainer container, GoRouter router) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp.router(routerConfig: router),
  );
}

String _currentPath(GoRouter router) =>
    router.routerDelegate.currentConfiguration.uri.path;

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [currentUserRoleProvider.overrideWithValue(UserRole.auditor)],
    );
  });

  tearDown(() => container.dispose());

  group('AdminHubScreen launcher', () {
    testWidgets('renders grouped registry cards', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildHub(container, router));
      await tester.pump();

      expect(find.text('CADASTROS & RECURSOS'), findsOneWidget);
      expect(find.text('Motoristas'), findsOneWidget);
      expect(find.text('Contratos'), findsOneWidget);
    });

    testWidgets('tapping a card navigates to its screen route', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildHub(container, router));
      await tester.pump();

      await tester.tap(find.text('Motoristas'));
      await tester.pumpAndSettle();

      expect(_currentPath(router), AdminNav.drivers.path);
    });

    testWidgets('renders onboarding banner and navigates when clicked', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final customContainer = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWithValue(UserRole.auditor),
          onboardingProgressProvider.overrideWithValue(
            const OnboardingProgress(
              steps: [
                OnboardingStep(
                  label: 'Contratantes',
                  description: 'Cadastre a entidade contratante.',
                  isFulfilled: false,
                  destination: AdminNav.contractors,
                ),
              ],
              completedCount: 0,
              isComplete: false,
            ),
          ),
        ],
      );
      addTearDown(customContainer.dispose);

      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildHub(customContainer, router));
      await tester.pump();

      expect(
        find.text('Passo 1 de 5: Configurar Contratantes'),
        findsOneWidget,
      );
      expect(find.text('CONFIGURAR AGORA'), findsOneWidget);

      await tester.tap(find.text('CONFIGURAR AGORA'));
      await tester.pumpAndSettle();

      expect(_currentPath(router), AdminNav.contractors.path);
    });

    testWidgets('hides onboarding banner when onboarding is complete', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final customContainer = ProviderContainer(
        overrides: [
          currentUserRoleProvider.overrideWithValue(UserRole.auditor),
          onboardingProgressProvider.overrideWithValue(
            const OnboardingProgress(
              steps: [],
              completedCount: 5,
              isComplete: true,
            ),
          ),
        ],
      );
      addTearDown(customContainer.dispose);

      final router = _hubRouter();
      addTearDown(router.dispose);

      await tester.pumpWidget(_buildHub(customContainer, router));
      await tester.pump();

      expect(find.textContaining('Passo'), findsNothing);
      expect(find.text('CONFIGURAR AGORA'), findsNothing);
    });
  });
}
