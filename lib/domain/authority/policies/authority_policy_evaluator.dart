import 'package:veraprob/domain/authority/core/authority_types.dart';
import 'package:veraprob/domain/authority/decision/authorization_decision.dart'; // O context estava dentro do arquivo de decision

/// Domain Port: Evaluates an Operational Action against a Context to yield a Decision.
///
/// This defines WHAT the semantic rules are, ignorant of HOW they are invoked.
/// It does not mutate anything; it is a pure function-like service.
abstract class AuthorityPolicyEvaluator {
  /// Evaluates an intention.
  ///
  /// The [targetRef] helps advanced policies check entity-level metadata
  /// (e.g., checking if the specific Trip is already resolved).
  Future<AuthorizationDecision> evaluate({
    required OperationalActionType actionType,
    required AuthorizationContext context,
    required TargetRef targetRef,
  });
}
