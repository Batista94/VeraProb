import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/resources/tabs/routes_tab.dart';
import 'package:veraprob/features/admin/providers/routes_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

Widget _wrap(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: Scaffold(body: RoutesTab())),
);

void main() {
  group('RoutesTab', () {
    testWidgets('renders empty state when route list is empty', (tester) async {
      await tester.pumpWidget(
        _wrap([
          routesListProvider.overrideWith((ref) async => <TransitRoute>[]),
          currentUserRoleProvider.overrideWithValue(UserRole.auditor),
        ]),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(RoutesTab), findsOneWidget);
      expect(find.text('Nenhuma rota cadastrada ainda.'), findsOneWidget);
    });
  });
}
