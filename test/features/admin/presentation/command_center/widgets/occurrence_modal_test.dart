import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/operational_control/operational_control_facade.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/features/admin/presentation/command_center/widgets/occurrence_modal.dart';
import 'package:veraprob/state/providers/authority_providers.dart';

class MockOperationalControlFacade extends Mock
    implements OperationalControlFacade {}

void main() {
  late MockOperationalControlFacade mockFacade;

  setUp(() {
    mockFacade = MockOperationalControlFacade();
    registerFallbackValue(EventType.manualOverride);
  });

  Widget buildModal() {
    return ProviderScope(
      overrides: [
        operationalControlFacadeProvider.overrideWithValue(mockFacade),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: OccurrenceModal(tripId: 'trip-001', tripLabel: 'Rota 01'),
        ),
      ),
    );
  }

  group('OccurrenceModal', () {
    testWidgets('renders idle state', (tester) async {
      await tester.pumpWidget(buildModal());
      await tester.pumpAndSettle();

      expect(find.text('Registrar Ocorrência'), findsOneWidget);
      expect(find.text('Rota 01'), findsOneWidget);
    });

    testWidgets('shows domain SnackBar on UnauthorizedActionException', (
      tester,
    ) async {
      when(
        () => mockFacade.createTripEvent(
          tripId: any(named: 'tripId'),
          type: any(named: 'type'),
          metadata: any(named: 'metadata'),
          notes: any(named: 'notes'),
        ),
      ).thenThrow(const UnauthorizedActionException('sem permissão'));

      await tester.pumpWidget(buildModal());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirmar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('Acesso Negado'), findsOneWidget);
    });
  });
}
