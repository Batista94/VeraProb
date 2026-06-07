import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/features/admin/presentation/screens/contracts_screen.dart';
import 'package:veraprob/state/providers/contract_providers.dart';

final _now = DateTime.utc(2026, 1, 1);
final _future = DateTime.utc(2027, 1, 1);

final _contracts = [
  ContractSummaryView(
    id: 'c-1',
    name: 'Contrato Alpha',
    contractorName: 'ACME Transportes',
    status: ContractStatusView.active,
    validFromUtc: _now,
    validUntilUtc: _future,
    createdAtUtc: _now,
    planCount: 1,
    activePlanVersion: 1,
    totalSetsInProgress: 0,
    slaHealthBps: 9500,
  ),
  ContractSummaryView(
    id: 'c-2',
    name: 'Contrato Beta',
    contractorName: 'Beta Logística',
    status: ContractStatusView.active,
    validFromUtc: _now,
    validUntilUtc: _future,
    createdAtUtc: _now,
    planCount: 0,
    activePlanVersion: 0,
    totalSetsInProgress: 0,
    slaHealthBps: 0,
  ),
  ContractSummaryView(
    id: 'c-3',
    name: 'Gama SLA',
    contractorName: 'ACME Transportes',
    status: ContractStatusView.draft,
    validFromUtc: _now,
    validUntilUtc: _future,
    createdAtUtc: _now,
    planCount: 0,
    activePlanVersion: 0,
    totalSetsInProgress: 0,
    slaHealthBps: 0,
  ),
];

Widget _buildScreen() {
  return ProviderScope(
    overrides: [
      contractListProvider.overrideWith((_) => Future.value(_contracts)),
      selectedContractIdProvider.overrideWithBuild((ref, notifier) => null),
    ],
    child: const MaterialApp(home: Scaffold(body: ContractsScreen())),
  );
}

void main() {
  group('ContractsScreen — search', () {
    testWidgets('shows all contracts when search is empty', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Contrato Alpha'), findsOneWidget);
      expect(find.text('Contrato Beta'), findsOneWidget);
      expect(find.text('Gama SLA'), findsOneWidget);
    });

    testWidgets('filters by contract name', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('contract_search_field'));
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'alpha');
      await tester.pump();

      expect(find.text('Contrato Alpha'), findsOneWidget);
      expect(find.text('Contrato Beta'), findsNothing);
      expect(find.text('Gama SLA'), findsNothing);
    });

    testWidgets('filters by contractor name', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('contract_search_field'));
      await tester.enterText(searchField, 'beta logística');
      await tester.pump();

      expect(find.text('Contrato Beta'), findsOneWidget);
      expect(find.text('Contrato Alpha'), findsNothing);
      expect(find.text('Gama SLA'), findsNothing);
    });

    testWidgets('search stacks with status filter', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      // Both c-1 and c-3 belong to ACME Transportes
      // but c-3 is draft, c-1 is active
      final searchField = find.byKey(const Key('contract_search_field'));
      await tester.enterText(searchField, 'ACME');
      await tester.pump();

      expect(find.text('Contrato Alpha'), findsOneWidget); // active, ACME
      expect(find.text('Gama SLA'), findsOneWidget); // draft, ACME
      expect(find.text('Contrato Beta'), findsNothing);
    });

    testWidgets('is case-insensitive', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      final searchField = find.byKey(const Key('contract_search_field'));
      await tester.enterText(searchField, 'GAMA');
      await tester.pump();

      expect(find.text('Gama SLA'), findsOneWidget);
      expect(find.text('Contrato Alpha'), findsNothing);
      expect(find.text('Contrato Beta'), findsNothing);
    });

    testWidgets('does not overflow on narrow screens', (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Gestão de Contratos'), findsOneWidget);
    });
  });
}
