import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/features/admin/presentation/resources/tabs/vehicles_tab.dart';
import 'package:veraprob/features/admin/providers/vehicles_provider.dart';
import 'package:veraprob/state/providers/auth_providers.dart';

Widget _wrap(List<Override> overrides) => ProviderScope(
  overrides: overrides,
  child: const MaterialApp(home: Scaffold(body: VehiclesTab())),
);

void main() {
  group('VehiclesTab', () {
    testWidgets('renders error state when filteredVehiclesProvider fails', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap([
          filteredVehiclesProvider.overrideWithValue(
            AsyncError(Exception('test'), StackTrace.empty),
          ),
          currentUserRoleProvider.overrideWithValue(UserRole.auditor),
        ]),
      );
      await tester.pump();
      expect(
        find.text('Não foi possível carregar os veículos agora.'),
        findsOneWidget,
      );
    });

    testWidgets('renders empty state when vehicle list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap([
          filteredVehiclesProvider.overrideWithValue(const AsyncData([])),
          currentUserRoleProvider.overrideWithValue(UserRole.auditor),
        ]),
      );
      await tester.pump();
      expect(find.byType(VehiclesTab), findsOneWidget);
    });
  });
}
