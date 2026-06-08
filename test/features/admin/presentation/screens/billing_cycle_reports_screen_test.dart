import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/screens/billing_cycle_reports_screen.dart';
import 'package:veraprob/state/providers/contract_providers.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/application/sla_audit/projections/contract_summary_view.dart';
import 'package:veraprob/application/sla_audit/projections/contract_status_view.dart';

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
];

Widget _buildScreen() {
  return ProviderScope(
    overrides: [
      contractListProvider.overrideWith((_) => Future.value(_contracts)),
      currentOrganizationIdProvider.overrideWith((ref) => 'test-org-id'),
    ],
    child: const MaterialApp(home: Scaffold(body: BillingCycleReportsScreen())),
  );
}

void main() {
  group('BillingCycleReportsScreen', () {
    testWidgets('loads successfully and does not overflow on narrow screens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(_buildScreen());
      await tester.pumpAndSettle();

      expect(find.text('Todos os contratos'), findsOneWidget);
    });
  });
}
