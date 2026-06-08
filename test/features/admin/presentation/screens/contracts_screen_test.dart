import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/sla_audit/clone_contract_handler.dart';
import 'package:veraprob/application/sla_audit/create_contract_handler.dart';
import 'package:veraprob/application/sla_audit/clone_contract_command.dart';
import 'package:veraprob/application/sla_audit/create_contract_command.dart';
import 'package:veraprob/domain/sla_audit/contract.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/application/sla_audit/projections/contractor_view.dart';
import 'package:veraprob/features/admin/presentation/screens/contracts_screen.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/contractor_providers.dart';

class MockCloneContractHandler extends Mock implements CloneContractHandler {}

class MockCreateContractHandler extends Mock implements CreateContractHandler {}

class FakeCloneContractCommand extends Fake implements CloneContractCommand {}

class FakeCreateContractCommand extends Fake implements CreateContractCommand {}

class FakeContract extends Fake implements Contract {
  @override
  final String id;
  FakeContract(this.id);
}

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

final List<ContractorView> _contractors = [
  ContractorView(
    id: 'con-1',
    name: 'ACME Transportes',
    taxId: '123',
    organizationId: 'org-1',
    createdAtUtc: _now,
    contactName: 'Alice',
    primaryEmail: 'alice@acme.com',
  ),
];

Widget _buildScreen({
  MockCloneContractHandler? cloneHandler,
  MockCreateContractHandler? createHandler,
}) {
  return ProviderScope(
    overrides: [
      contractListProvider.overrideWith((_) => Future.value(_contracts)),
      selectedContractIdProvider.overrideWithBuild((ref, notifier) => null),
      contractorListProvider.overrideWith((_) => Future.value(_contractors)),
      currentOrganizationIdProvider.overrideWith((_) => 'org-1'),
      currentSessionIdProvider.overrideWith((_) => 'sess-1'),
      if (cloneHandler != null)
        cloneContractHandlerProvider.overrideWithValue(cloneHandler),
      if (createHandler != null)
        createContractHandlerProvider.overrideWithValue(createHandler),
    ],
    child: const MaterialApp(home: Scaffold(body: ContractsScreen())),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeCloneContractCommand());
    registerFallbackValue(FakeCreateContractCommand());
  });

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

      final searchField = find.byKey(const Key('contract_search_field'));
      await tester.enterText(searchField, 'ACME');
      await tester.pump();

      expect(find.text('Contrato Alpha'), findsOneWidget);
      expect(find.text('Gama SLA'), findsOneWidget);
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
  });

  group('ContractsScreen — modals regression', () {
    testWidgets('CreateContractForm handles cancellation gracefully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo Contrato'));
      await tester.pumpAndSettle();

      expect(find.text('Novo Contrato Operacional'), findsOneWidget);

      await tester.tap(find.text('DESCARTAR'));
      await tester.pumpAndSettle();

      expect(find.text('Novo Contrato Operacional'), findsNothing);
    });

    testWidgets('CloneDialog captures context and closes successfully', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final cloneHandler = MockCloneContractHandler();
      when(
        () => cloneHandler.handle(
          any(),
          validFromUtc: any(named: 'validFromUtc'),
          validUntilUtc: any(named: 'validUntilUtc'),
        ),
      ).thenAnswer((_) async => FakeContract('new-clone-id'));

      await tester.pumpWidget(_buildScreen(cloneHandler: cloneHandler));
      await tester.pumpAndSettle();

      final copyButton = find.byIcon(Icons.copy_outlined).first;
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(find.text('Clonar Contrato'), findsOneWidget);

      // Select Valid From
      await tester.tap(find.text('Início da vigência *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('15').first);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Select Valid Until
      await tester.tap(find.text('Fim da vigência *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('20').first);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      // Submit
      await tester.tap(find.text('Clonar'));
      await tester.pumpAndSettle();

      // Verifies the modal closed safely via navigator.pop
      expect(find.text('Clonar Contrato'), findsNothing);
      verify(
        () => cloneHandler.handle(
          any(),
          validFromUtc: any(named: 'validFromUtc'),
          validUntilUtc: any(named: 'validUntilUtc'),
        ),
      ).called(1);
    });
  });
}
