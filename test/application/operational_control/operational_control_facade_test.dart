import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/application/operational_control/operational_control_facade.dart';
import 'package:veraprob/domain/auth/i_auth_repository.dart';
import 'package:veraprob/domain/auth/auth_user.dart';
import 'package:veraprob/domain/enums/user_role.dart';

class MockCommandBus extends Mock implements OperationalCommandBus {}

class MockAuthRepository extends Mock implements IAuthRepository {}

class FakeCommand extends Fake implements OperationalCommand {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeCommand());
  });

  group('OperationalControlFacade - INV-1 Compliance', () {
    late MockCommandBus mockBus;
    late MockAuthRepository mockAuth;
    late OperationalControlFacade facade;

    setUp(() {
      mockBus = MockCommandBus();
      mockAuth = MockAuthRepository();
      facade = OperationalControlFacade(mockBus, mockAuth);
    });

    test('resolveAlert success with authenticated user', () async {
      when(() => mockAuth.getCurrentUser()).thenAnswer(
        (_) async => const AuthUser(
          id: 'user-1',
          email: 'test@example.com',
          tenantId: 'org-1',
          role: UserRole.operator,
        ),
      );
      when(() => mockBus.dispatch(any())).thenAnswer((_) async {});

      await facade.resolveAlert(tripId: 't1');

      verify(() => mockAuth.getCurrentUser()).called(1);
      verify(() => mockBus.dispatch(any())).called(1);
    });

    test('resolveAlert throws when no authenticated session', () async {
      when(() => mockAuth.getCurrentUser()).thenAnswer((_) async => null);

      expect(
        () => facade.resolveAlert(tripId: 't1'),
        throwsA(
          isA<UnauthorizedActionException>().having(
            (e) => e.reason,
            'reason',
            'No authenticated session',
          ),
        ),
      );

      verify(() => mockAuth.getCurrentUser()).called(1);
      verifyNever(() => mockBus.dispatch(any()));
    });

    test(
      'resolveAlert propagates UnauthorizedActionException from bus',
      () async {
        when(() => mockAuth.getCurrentUser()).thenAnswer(
          (_) async => const AuthUser(
            id: 'user-1',
            email: 'test@example.com',
            tenantId: 'org-1',
            role: UserRole.operator,
          ),
        );
        when(
          () => mockBus.dispatch(any()),
        ).thenThrow(const UnauthorizedActionException('denied'));

        expect(
          () => facade.resolveAlert(tripId: 't1'),
          throwsA(isA<UnauthorizedActionException>()),
        );
      },
    );

    test('createTripEvent success with authenticated user', () async {
      when(() => mockAuth.getCurrentUser()).thenAnswer(
        (_) async => const AuthUser(
          id: 'user-1',
          email: 'test@example.com',
          tenantId: 'org-1',
          role: UserRole.operator,
        ),
      );
      when(() => mockBus.dispatch(any())).thenAnswer((_) async {});

      await facade.createTripEvent(tripId: 't1', type: EventType.statusChange);

      verify(() => mockAuth.getCurrentUser()).called(1);
      verify(() => mockBus.dispatch(any())).called(1);
    });

    test('createTripEvent throws when no authenticated session', () async {
      when(() => mockAuth.getCurrentUser()).thenAnswer((_) async => null);

      expect(
        () =>
            facade.createTripEvent(tripId: 't1', type: EventType.statusChange),
        throwsA(
          isA<UnauthorizedActionException>().having(
            (e) => e.reason,
            'reason',
            'No authenticated session',
          ),
        ),
      );

      verify(() => mockAuth.getCurrentUser()).called(1);
      verifyNever(() => mockBus.dispatch(any()));
    });

    test(
      'createTripEvent propagates UnauthorizedActionException from bus',
      () async {
        when(() => mockAuth.getCurrentUser()).thenAnswer(
          (_) async => const AuthUser(
            id: 'user-1',
            email: 'test@example.com',
            tenantId: 'org-1',
            role: UserRole.operator,
          ),
        );
        when(
          () => mockBus.dispatch(any()),
        ).thenThrow(const UnauthorizedActionException('denied'));

        expect(
          () => facade.createTripEvent(
            tripId: 't1',
            type: EventType.statusChange,
          ),
          throwsA(isA<UnauthorizedActionException>()),
        );
      },
    );

    test('UnauthorizedActionException toString', () {
      const ex = UnauthorizedActionException('some reason');
      expect(ex.toString(), contains('some reason'));
    });
  });
}
