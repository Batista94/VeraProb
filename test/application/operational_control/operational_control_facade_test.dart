import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/application/operational_control/operational_control_facade.dart';

class MockCommandBus extends Mock implements OperationalCommandBus {}

class FakeCommand extends Fake implements OperationalCommand {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeCommand());
  });

  group('OperationalControlFacade & Exceptions Coverage', () {
    late MockCommandBus mockBus;
    late OperationalControlFacade facade;

    setUp(() {
      mockBus = MockCommandBus();
      facade = OperationalControlFacade(mockBus);
    });

    test('resolveAlert success', () async {
      when(() => mockBus.dispatch(any())).thenAnswer((_) async {});
      await facade.resolveAlert(tripId: 't1', simulateRole: 'op');
      verify(() => mockBus.dispatch(any())).called(1);
    });

    test('resolveAlert error', () async {
      when(
        () => mockBus.dispatch(any()),
      ).thenThrow(UnauthorizedActionException('denied'));
      expect(
        () => facade.resolveAlert(tripId: 't1', simulateRole: 'op'),
        throwsA(isA<UnauthorizedActionException>()),
      );
    });

    test('createTripEvent success', () async {
      when(() => mockBus.dispatch(any())).thenAnswer((_) async {});
      await facade.createTripEvent(tripId: 't1', type: EventType.statusChange);
      verify(() => mockBus.dispatch(any())).called(1);
    });

    test('createTripEvent error', () async {
      when(
        () => mockBus.dispatch(any()),
      ).thenThrow(UnauthorizedActionException('denied'));
      expect(
        () =>
            facade.createTripEvent(tripId: 't1', type: EventType.statusChange),
        throwsA(isA<UnauthorizedActionException>()),
      );
    });

    test('UnauthorizedActionException toString', () {
      final ex = UnauthorizedActionException('some reason');
      expect(ex.toString(), contains('some reason'));
    });
  });
}
