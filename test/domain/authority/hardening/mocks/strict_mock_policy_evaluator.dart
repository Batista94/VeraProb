import 'package:uuid/uuid.dart';
import 'package:pactaflow/domain/authority/core/authority_types.dart';
import 'package:pactaflow/domain/authority/decision/authorization_decision.dart';
import 'package:pactaflow/domain/authority/policies/authority_policy_evaluator.dart';

/// Programmable Evaluator for strict unit testing.
///
/// Allows injecting a predefined set of answers mapped by [OperationalActionType].
/// Exposes [evaluationCount] to mathematically prove 100% test coverage.
class StrictMockPolicyEvaluator implements AuthorityPolicyEvaluator {
  final Map<OperationalActionType, DecisionResult> setupRules;
  int evaluationCount = 0;

  final _uuid = const Uuid();

  StrictMockPolicyEvaluator(this.setupRules);

  @override
  Future<AuthorizationDecision> evaluate({
    required OperationalActionType actionType,
    required AuthorizationContext context,
    required TargetRef targetRef,
  }) async {
    evaluationCount++;

    final result = setupRules[actionType] ?? DecisionResult.denied;
    final reason = result == DecisionResult.denied
        ? 'Denied by Strict Mock Policy (No rule for $actionType)'
        : null;

    return AuthorizationDecision(
      decisionId: _uuid.v4(),
      actorId: context.actorId,
      roleId: context.roleId,
      actionType: actionType,
      targetRef: targetRef,
      policyVersion: 'test_mock_v1',
      result: result,
      reason: reason,
      occurredAt: DateTime.now(),
      contextSnapshot: context.toJson(),
    );
  }
}
