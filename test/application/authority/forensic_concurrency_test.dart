import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/authority/authorizing_command_bus.dart';
import 'package:veraprob/domain/authority/commands/trips/resolve_alert_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/repositories/forensic_decision_repository.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

import 'mocks/mock_mutator_service.dart';
import 'mocks/strict_mock_policy_evaluator.dart';

class FakeForensicRepository implements ForensicDecisionRepository {
  final List<AuthorizationDecision> ledger = [];
  int get ledgerCount => ledger.length;
  List<AuthorizationDecision> get testLedgerArray => ledger;
  @override
  Future<void> saveDecision(AuthorizationDecision decision) async =>
      ledger.add(decision);

  Future<List<AuthorizationDecision>> getDecisionsForTarget(
    TargetRef targetRef,
  ) async => ledger.where((d) => d.targetRef == targetRef).toList();
}

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Architecture Guardians: Forensic Concurrency Test', () {
    test(
      '5. Mass Concurrent Dispatches: Should maintain ledger consistency without dropping decisions',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.approved,
        });

        final ledger = FakeForensicRepository();
        final mutator = MockMutatorService();

        final testFixTime = DateTime.utc(2026, 4, 8, 12, 0, 0);
        final mockDateTime = MockDateTimeProvider();
        when(() => mockDateTime.nowUtc()).thenReturn(testFixTime.toUtc());

        AuthorizationContext mockSession() => AuthorizationContext(
          actorId: const ActorId('stress-actor'),
          roleId: const RoleId('stresser'),
          capturedAt: testFixTime,
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );

        // Act: Throw 100 simultaneous requests into the event loop
        final futures = <Future<void>>[];
        for (var i = 0; i < 100; i++) {
          final command = ResolveAlertCommand(tripId: 'concurrent_trip_$i');
          futures.add(bus.dispatch(command));
        }

        await Future.wait(futures);

        // Assert
        expect(
          evaluator.evaluationCount,
          100,
          reason:
              'Evaluator must have received every single concurrent intention.',
        );

        expect(
          ledger.ledgerCount,
          100,
          reason:
              'The Append-Only Forensics must safely lock and queue all 100 entries with no gaps.',
        );

        expect(
          mutator.callCount,
          100,
          reason:
              'Mutator must fire exactly 100 times, confirming no short-circuit drops.',
        );
      },
    );
  });
}
