import 'package:uuid/uuid.dart';

import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart';
import 'authority_policy_evaluator.dart';

/// In-Memory Stub for Phase 3 conceptual validation.
///
/// In production, this would load explicit RBAC / PBAC policies.
/// For testing, it statically denies 'resolve_alert' if role is 'level1_operator'
/// to prove interception behavior.
class InMemoryPolicyEvaluator implements AuthorityPolicyEvaluator {
  final _uuid = const Uuid();

  @override
  Future<AuthorizationDecision> evaluate({
    required OperationalActionType actionType,
    required AuthorizationContext context,
    required TargetRef targetRef,
    required DateTime nowUtc,
  }) async {
    // Very dummy Mock Policy for demonstration purposes
    DecisionResult result = DecisionResult.approved;
    String? reason;

    if (actionType == OperationalActionType.resolveAlert) {
      if (context.roleId.value == 'level1_operator') {
        result = DecisionResult.denied;
        reason =
            'Operadores Nível 1 não têm escopo para forçar resolução de incidentes.';
      }
    }

    return AuthorizationDecision(
      decisionId: _uuid.v4(),
      actorId: context.actorId,
      roleId: context.roleId,
      actionType: actionType,
      targetRef: targetRef,
      policyVersion: 'mock_v1_0.0',
      result: result,
      reason: reason,
      occurredAt: nowUtc,
      contextSnapshot: context.toJson(),
    );
  }
}
