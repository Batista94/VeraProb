import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/features/admin/presentation/screens/admin_hub_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/admin_providers.dart';

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (_, _, _) => true;
  }
}

Widget _buildHub() {
  return ProviderScope(
    overrides: [
      currentOperatorIdProvider.overrideWithValue('test-user-id'),
      currentOperatorNameProvider.overrideWithValue('Operador Teste'),
      orgMembersProvider.overrideWith((ref) => Future.value([])),
      orgInvitationsProvider.overrideWith((ref) => Future.value([])),
      orgSettingsProvider.overrideWith((ref) => Future.value(null)),
    ],
    child: const MaterialApp(home: AdminHubScreen()),
  );
}

void main() {
  setUp(() => HttpOverrides.global = _MockHttpOverrides());
  tearDown(() => HttpOverrides.global = null);

  group('AdminHubScreen', () {
    testWidgets('renders three tab labels', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHub());
      await tester.pump();

      expect(find.text('Ajustes'), findsOneWidget);
      expect(find.text('Equipe'), findsOneWidget);
      expect(find.text('Organização'), findsOneWidget);
    });

    testWidgets('renders settings content on first tab by default', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHub());
      await tester.pumpAndSettle();

      // SettingsScreen renders "CONFIGURAÇÕES DO SISTEMA"
      expect(find.text('CONFIGURAÇÕES DO SISTEMA'), findsOneWidget);
    });

    testWidgets('tab switch to Equipe shows user management content', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHub());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Equipe'));
      await tester.pumpAndSettle();

      expect(find.text('Gestão de Usuários'), findsOneWidget);
    });

    testWidgets('tab switch to Organização shows org settings content', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildHub());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Organização'));
      await tester.pumpAndSettle();

      expect(find.text('Configurações da Organização'), findsOneWidget);
    });
  });
}
