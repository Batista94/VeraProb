import 'package:flutter_test/flutter_test.dart';

import 'package:veraprob/application/authority/authorizing_command_bus.dart';
import 'package:veraprob/domain/authority/commands/trips/resolve_alert_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/repositories/in_memory_forensic_repository.dart';

import 'mocks/mock_mutator_service.dart';
import 'mocks/strict_mock_policy_evaluator.dart';

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

        final ledger = InMemoryForensicRepository();
        final mutator = MockMutatorService();

        AuthorizationContext mockSession() => AuthorizationContext(
          actorId: const ActorId('stress-actor'),
          roleId: const RoleId('stresser'),
          capturedAt: DateTime.now(),
        );

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
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
