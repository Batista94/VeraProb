import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/domain_exception.dart';
import 'rule_studio_command_service.dart';
import 'update_contractual_rule_command.dart';

/// Application handler for [UpdateContractualRuleCommand].
///
/// Transitions a contractual rule to a new version, preserving the full
/// audit history (INV-1: immutable ledger — old version is closed, never deleted).
///
/// Flow:
///   1. RBAC check ([canEditSlaRules])
///   2. Config key validation against rule type contract
///   3. Atomic RPC: close old version + insert new version
///   4. Return new rule UUID
class UpdateContractualRuleHandler {
  final RuleStudioCommandService _commandService;
  final RbacService _rbac;

  UpdateContractualRuleHandler({
    required RuleStudioCommandService commandService,
    required RbacService rbac,
  }) : _commandService = commandService,
       _rbac = rbac;

  /// Returns the UUID of the newly created rule version.
  ///
  /// Throws [DomainException] if:
  /// - Caller lacks [UserPermission.canEditSlaRules]
  /// - [newConfig] is missing required keys for the given [ruleType]
  Future<String> handle(UpdateContractualRuleCommand command) async {
    // 1. RBAC — before any I/O
    if (!_rbac.can(command.callerRole, UserPermission.canEditSlaRules)) {
      throw const DomainException('Unauthorized: canEditSlaRules required.');
    }

    // 2. Validate config keys match engine contract (mirrors DB constraint)
    _validateConfig(command);

    // 3. Atomic close + insert via RPC (atomicity guaranteed by Postgres)
    return _commandService.updateRule(
      contractId: command.contractId,
      oldRuleId: command.oldRuleId,
      ruleType: command.ruleType,
      newConfig: command.newConfig,
      evaluationOrder: command.evaluationOrder,
    );
  }

  void _validateConfig(UpdateContractualRuleCommand command) {
    final config = command.newConfig;
    final type = command.ruleType;

    final requiredKey = switch (type.value) {
      'MAX_TOLERANCE_DELAY' => 'threshold_minutes',
      'MAX_EVIDENCE_GAP' => 'max_gap_seconds',
      'MIN_GEOFENCE_COVERAGE' => 'min_dwell_seconds',
      'NO_SHOW_PENALTY' => 'penalty_amount_cents',
      _ => throw DomainException('Unknown rule type: ${type.value}'),
    };

    if (!config.containsKey(requiredKey)) {
      throw DomainException(
        'Rule config for ${type.value} must contain key "$requiredKey".',
      );
    }
  }
}
