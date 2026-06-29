import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/sla_execution_item_view.dart';
import 'package:veraprob/features/admin/presentation/screens/widgets/_sla_execution_detail_drawer.dart';
import 'package:veraprob/state/providers/auth_providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

void main() {
  final fakeItem = SlaExecutionItemView(
    setId: 'SET-001',
    contractId: 'CONTRACT-001',
    status: ExecutionStatus.planned,
    windowStartUtc: DateTime.utc(2026, 1, 1, 6),
    windowEndUtc: DateTime.utc(2026, 1, 1, 8),
    startLatitude: -23.55,
    startLongitude: -46.63,
    startRadiusMeters: 100,
    contractualValue: 50000,
    noShowPenaltyBps: 1000,
  );

  Widget buildDrawer() {
    return ProviderScope(
      overrides: [
        currentUserRoleProvider.overrideWith((ref) => UserRole.admin),
        currentOrganizationIdProvider.overrideWith((ref) => 'test-org'),
        currentOperatorIdProvider.overrideWith((ref) => 'user-001'),
        currentSessionIdProvider.overrideWith((ref) => 'session-001'),
      ],
      child: MaterialApp(
        home: Scaffold(body: SlaExecutionDetailDrawer(item: fakeItem)),
      ),
    );
  }

  group('SlaExecutionDetailDrawer', () {
    testWidgets('renders drawer with SET ID and contract info', (tester) async {
      await tester.pumpWidget(buildDrawer());
      await tester.pumpAndSettle();

      expect(find.text('SET-001'), findsOneWidget);
      expect(find.text('CONTRACT-001'), findsOneWidget);
    });
  });
}
