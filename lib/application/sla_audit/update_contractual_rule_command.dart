import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';

/// Immutable command DTO for updating a contractual rule configuration.
///
/// Contains ZERO logic. Carries only the data required by
/// [UpdateContractualRuleHandler] to version-transition a rule.
///
/// [organizationId] and [callerRole] must be injected from the
/// authenticated JWT — never from form input.
///
/// Set [oldRuleId] to null when creating the first version of a rule type
/// for a contract that has no rule set yet.
class UpdateContractualRuleCommand {
  final String organizationId;

  /// UUID of the target contract.
  final String contractId;

  /// UUID of the currently active rule version to close. Null = first version.
  final String? oldRuleId;

  final SlaRuleType ruleType;

  /// New configuration parameters. Keys must match the engine's config contract
  /// (e.g. 'min_dwell_seconds' for MIN_GEOFENCE_COVERAGE).
  final Map<String, dynamic> newConfig;

  final int evaluationOrder;

  /// Role of the user — sourced from JWT claim, never from user input.
  final UserRole callerRole;

  /// Session ID for tenant validation.
  final String sessionId;

  final DateTime effectiveAtUtc;

  const UpdateContractualRuleCommand({
    required this.organizationId,
    required this.contractId,
    this.oldRuleId,
    required this.ruleType,
    required this.newConfig,
    required this.evaluationOrder,
    required this.callerRole,
    required this.sessionId,
    required this.effectiveAtUtc,
  });
}
