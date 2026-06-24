import 'package:veraprob/domain/sla_audit/contractual_rule.dart';

/// Port: atomic rule version transition.
///
/// Implementations must guarantee that closing the old version and inserting
/// the new version happen in a single DB transaction (INV-1: no partial states).
///
/// Business logic (validation, RBAC) lives in [UpdateContractualRuleHandler].
/// This service is ONLY responsible for persistence atomicity.
abstract class RuleStudioCommandService {
  /// Transitions rule to a new version.
  ///
  /// Returns the UUID of the newly created rule version.
  Future<String> updateRule({
    required String contractId,
    required String? oldRuleId,
    required SlaRuleType ruleType,
    required Map<String, dynamic> newConfig,
    required int evaluationOrder,
    required DateTime effectiveAtUtc,
  });

  Future<String> scheduleRule({
    required String contractId,
    required String? oldRuleId,
    required SlaRuleType ruleType,
    required Map<String, dynamic> newConfig,
    required int evaluationOrder,
    required DateTime effectiveAtUtc,
  });

  Future<void> activateScheduledRule({required String ruleId});

  Future<void> retireRule({required String ruleId});
}
