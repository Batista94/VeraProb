import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/vehicle_detail_drawer.dart';
import 'package:veraprob/state/providers/fleet_providers.dart';

void main() {
  group('VehicleDetailDrawer error UI (UX-RAW-EXCEPTION guard)', () {
    final fakeTrip = OperationalTrip(
      id: 'trip-test-001',
      routeId: 'route-001',
      scheduledStart: DateTime.utc(2026, 1, 1, 6),
    );

    testWidgets('ledger load error shows sanitised domain message', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 900);
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            forensicLedgerProjectionProvider.overrideWith(
              (ref) => Future.error('network-fail'),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: VehicleDetailDrawer(trip: fakeTrip, onClose: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Não foi possível carregar o histórico do veículo.'),
        findsOneWidget,
      );
      expect(find.textContaining('network-fail'), findsNothing);
    });
  });
}
