import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:veraprob/application/authority/authorizing_command_bus.dart';
import 'package:veraprob/domain/authority/commands/trips/resolve_alert_command.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/repositories/in_memory_forensic_repository.dart';
import 'package:veraprob/application/authority/operational_command_bus.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

import 'mocks/mock_mutator_service.dart';
import 'mocks/strict_mock_policy_evaluator.dart';

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

/// Unmapped dummy command to test error bounding
class RogueCommand extends OperationalCommand {
  const RogueCommand();
  @override
  TargetRef get targetRef => const TargetRef('system', 'rogue');
  @override
  String? get targetOrganizationId => null;
  @override
  List<Object?> get props => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Architecture Guardians: AuthorizingCommandBus', () {
    late InMemoryForensicRepository ledger;
    late MockMutatorService mutator;
    late MockDateTimeProvider mockDateTime;

    final testFixTime = DateTime.utc(2026, 4, 8, 12, 0, 0);

    AuthorizationContext mockSession() => AuthorizationContext(
      actorId: const ActorId('test-actor'),
      roleId: const RoleId('test-role'),
      capturedAt: testFixTime,
    );

    setUp(() {
      ledger = InMemoryForensicRepository();
      mutator = MockMutatorService();
      mockDateTime = MockDateTimeProvider();
      when(() => mockDateTime.now()).thenReturn(testFixTime.toUtc());
    });

    test(
      '1. The Golden Path (Approved Mutator): Should log APPROVED and call Mutator 1 time',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.approved,
        });

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 't-123');

        // Act
        await bus.dispatch(command);

        // Assert
        expect(
          evaluator.evaluationCount,
          1,
          reason: 'Evaluator must be called exactly once.',
        );
        expect(ledger.ledgerCount, 1, reason: 'Decision must be recorded.');

        final decision = ledger.testLedgerArray;
        expect(decision.first.result, DecisionResult.approved);

        expect(
          mutator.callCount,
          1,
          reason: 'Mutator must be executed when APPROVED.',
        );
      },
    );

    test(
      '2. The Iron Gate (Denied Mutator): Should log DENIED and call Mutator 0 times',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.denied,
        });

        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 't-999');

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnauthorizedActionException>()),
          reason: 'Command Bus must instantly throw Unauthorized Exception.',
        );

        // We need to wait a tick for the exception flow to settle and check counters
        await Future.delayed(Duration.zero);

        expect(
          evaluator.evaluationCount,
          1,
          reason: 'Evaluator must be called exactly once.',
        );
        expect(
          ledger.ledgerCount,
          1,
          reason: 'The DENIED attempt MUST be forensically logged.',
        );

        final logs = ledger.testLedgerArray;
        expect(logs.first.result, DecisionResult.denied);

        expect(
          mutator.callCount,
          0,
          reason:
              'Mutator MUST NOT BE CALLED under any circumstance when DENIED.',
        );
      },
    );

    test(
      '3. The Unmapped Rogue Command: Should fail mapping, skipping Evaluator and Mutator',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({});
        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );
        const command = RogueCommand();

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<UnimplementedError>()),
          reason: 'Mapper must reject unknown commands before Evaluation',
        );

        await Future.delayed(Duration.zero);

        expect(
          evaluator.evaluationCount,
          0,
          reason: 'Evaluator never touched.',
        );
        expect(ledger.ledgerCount, 0, reason: 'Ledger never touched.');
        expect(mutator.callCount, 0, reason: 'Mutator never touched.');
      },
    );

    test(
      '4. Atomic Mutator Failure: Should still retain the APPROVED forensic log even if system crashes downstream',
      () async {
        // Arrange
        final evaluator = StrictMockPolicyEvaluator({
          OperationalActionType.resolveAlert: DecisionResult.approved,
        });

        mutator.shouldThrowError = true; // Simulates backend crash mid-mutation
        final bus = AuthorizingCommandBus(
          evaluator,
          ledger,
          mockSession,
          mutator,
          mockDateTime,
        );
        const command = ResolveAlertCommand(tripId: 't-crash');

        // Act & Assert
        expect(
          () => bus.dispatch(command),
          throwsA(isA<Exception>()),
          reason: 'Underlying service failure should bubble up.',
        );

        await Future.delayed(Duration.zero);

        expect(evaluator.evaluationCount, 1);

        // CRITICAL: The decision was taken AND LOGGED before the downstream crash.
        expect(
          ledger.ledgerCount,
          1,
          reason: 'Decision was successfully appended before the exception.',
        );
        expect(
          mutator.callCount,
          1,
          reason: 'Execution started, then crashed.',
        );

        final logs = ledger.testLedgerArray;
        expect(
          logs.first.result,
          DecisionResult.approved,
        ); // It was allowed to happen.
      },
    );
  });
}
