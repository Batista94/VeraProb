import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'package:veraprob/domain/authority/policies/in_memory_policy_evaluator.dart';

void main() {
  late InMemoryPolicyEvaluator evaluator;

  AuthorizationContext makeContext({required String roleId}) {
    return AuthorizationContext(
      actorId: const ActorId('user-123'),
      roleId: RoleId(roleId),
      capturedAt: DateTime.utc(2026, 3, 1, 10, 0),
    );
  }

  setUp(() {
    evaluator = InMemoryPolicyEvaluator();
  });

  group('InMemoryPolicyEvaluator', () {
    test('approves resolveAlert for a non-restricted role', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'supervisor'),
        targetRef: const TargetRef('trip', 'trip-1'),
      );

      expect(decision.isApproved, isTrue);
      expect(decision.result, DecisionResult.approved);
    });

    test('denies resolveAlert for level1_operator', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.resolveAlert,
        context: makeContext(roleId: 'level1_operator'),
        targetRef: const TargetRef('trip', 'trip-1'),
      );

      expect(decision.isApproved, isFalse);
      expect(decision.result, DecisionResult.denied);
      expect(decision.reason, isNotNull);
    });

    test('approves all other action types for level1_operator', () async {
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.acknowledgeAlert,
        context: makeContext(roleId: 'level1_operator'),
        targetRef: const TargetRef('trip', 'trip-1'),
      );

      expect(decision.isApproved, isTrue);
    });

    test('decision carries actor and role context', () async {
      final context = makeContext(roleId: 'supervisor');
      final decision = await evaluator.evaluate(
        actionType: OperationalActionType.acknowledgeAlert,
        context: context,
        targetRef: const TargetRef('trip', 'trip-2'),
      );

      expect(decision.actorId, context.actorId);
      expect(decision.roleId, context.roleId);
      expect(decision.decisionId, isNotEmpty);
    });
  });
}
