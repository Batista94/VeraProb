import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/screens/admin_hub_screen.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
import 'package:veraprob/features/admin/providers/onboarding_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

Widget _buildHub(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: Scaffold(body: AdminHubScreen())),
  );
}

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

      await tester.pumpWidget(_buildHub(container));
      await tester.pump();

      expect(find.text('CADASTROS & RECURSOS'), findsOneWidget);
      expect(find.text('Motoristas'), findsOneWidget);
      expect(find.text('Contratos'), findsOneWidget);
    });

    testWidgets('tapping a card navigates to its screen index', (tester) async {
      tester.view.physicalSize = const Size(1400, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHub(container));
      await tester.pump();

      await tester.tap(find.text('Motoristas'));
      await tester.pump();

      expect(container.read(adminIndexProvider), AdminNav.drivers.index);
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

      await tester.pumpWidget(_buildHub(customContainer));
      await tester.pump();

      expect(
        find.text('Passo 1 de 5: Configurar Contratantes'),
        findsOneWidget,
      );
      expect(find.text('CONFIGURAR AGORA'), findsOneWidget);

      await tester.tap(find.text('CONFIGURAR AGORA'));
      await tester.pump();

      expect(
        customContainer.read(adminIndexProvider),
        AdminNav.contractors.index,
      );
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

      await tester.pumpWidget(_buildHub(customContainer));
      await tester.pump();

      expect(find.textContaining('Passo'), findsNothing);
      expect(find.text('CONFIGURAR AGORA'), findsNothing);
    });
  });
}
