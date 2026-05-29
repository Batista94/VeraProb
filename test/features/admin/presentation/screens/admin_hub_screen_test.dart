import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/screens/admin_hub_screen.dart';
import 'package:veraprob/features/admin/providers/admin_navigation_provider.dart';
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
  });
}
