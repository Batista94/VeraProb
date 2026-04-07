import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/contractor_view.dart';
import 'package:veraprob/features/admin/presentation/screens/contractor_management_screen.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';

final _now = DateTime.utc(2026, 1, 1);

final _contractors = [
  ContractorView(
    id: '1',
    organizationId: 'org-1',
    name: 'ACME Transportes',
    taxId: '12.345.678/0001-90',
    primaryEmail: 'acme@test.com',
    contactName: 'Carlos',
    createdAtUtc: _now,
  ),
  ContractorView(
    id: '2',
    organizationId: 'org-1',
    name: 'Beta Logística',
    taxId: '98.765.432/0001-11',
    primaryEmail: 'beta@test.com',
    contactName: 'Ana',
    createdAtUtc: _now,
  ),
  ContractorView(
    id: '3',
    organizationId: 'org-1',
    name: 'Gama Fretes',
    taxId: null,
    primaryEmail: 'gama@test.com',
    contactName: 'João',
    createdAtUtc: _now,
  ),
];

Widget _buildScreen() {
  return ProviderScope(
    overrides: [
      contractorListProvider.overrideWith((_) => Future.value(_contractors)),
    ],
    child: const MaterialApp(home: ContractorManagementScreen()),
  );
}

void main() {
  group('ContractorManagementScreen — search', () {
    testWidgets('shows all contractors when search is empty', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('ACME Transportes'), findsOneWidget);
      expect(find.text('Beta Logística'), findsOneWidget);
      expect(find.text('Gama Fretes'), findsOneWidget);
    });

    testWidgets('filters by contractor name', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('contractor_search_field'));
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'acme');
      await tester.pump();

      expect(find.text('ACME Transportes'), findsOneWidget);
      expect(find.text('Beta Logística'), findsNothing);
      expect(find.text('Gama Fretes'), findsNothing);
    });

    testWidgets('filters by CNPJ (taxId)', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('contractor_search_field'));
      await tester.enterText(searchField, '98.765');
      await tester.pump();

      expect(find.text('ACME Transportes'), findsNothing);
      expect(find.text('Beta Logística'), findsOneWidget);
      expect(find.text('Gama Fretes'), findsNothing);
    });

    testWidgets('shows all contractors when query is cleared', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('contractor_search_field'));
      await tester.enterText(searchField, 'gama');
      await tester.pump();
      expect(find.text('ACME Transportes'), findsNothing);

      await tester.enterText(searchField, '');
      await tester.pump();
      expect(find.text('ACME Transportes'), findsOneWidget);
      expect(find.text('Beta Logística'), findsOneWidget);
      expect(find.text('Gama Fretes'), findsOneWidget);
    });

    testWidgets('is case-insensitive', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('contractor_search_field'));
      await tester.enterText(searchField, 'BETA');
      await tester.pump();

      expect(find.text('Beta Logística'), findsOneWidget);
      expect(find.text('ACME Transportes'), findsNothing);
    });
  });
}
