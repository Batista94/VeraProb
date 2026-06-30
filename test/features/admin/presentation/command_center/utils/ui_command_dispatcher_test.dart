import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/features/admin/presentation/command_center/utils/ui_command_dispatcher.dart';
import 'package:veraprob/state/providers/authority_providers.dart';

class _ThrowingBus implements OperationalCommandBus {
  @override
  Future<void> dispatch(OperationalCommand command) async {
    throw Exception('network-crash');
  }
}

class _DispatchButton extends ConsumerWidget {
  const _DispatchButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => UiCommandDispatcher.dispatch(
        context,
        ref,
        const UpdateTripStatusCommand(
          tripId: 'trip-001',
          newStatus: TripStatus.enRoute,
        ),
      ),
      child: const Text('Despachar'),
    );
  }
}

void main() {
  group('UiCommandDispatcher catch block (UX-RAW-EXCEPTION guard)', () {
    testWidgets('generic exception shows sanitised domain message', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            operationalCommandBusProvider.overrideWithValue(_ThrowingBus()),
          ],
          child: const MaterialApp(home: Scaffold(body: _DispatchButton())),
        ),
      );

      await tester.tap(find.text('Despachar'));
      await tester.pump();

      expect(
        find.text('Falha ao executar o comando operacional. Tente novamente.'),
        findsOneWidget,
      );
      expect(find.textContaining('network-crash'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
    });
  });
}
