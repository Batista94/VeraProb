import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'rule_studio_command_service.dart';
import 'update_contractual_rule_command.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

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
  final TenantValidationService _tenantValidator;
  final RuleStudioCommandService _commandService;
  final RbacService _rbac;
  final IDateTimeProvider _clock;

  UpdateContractualRuleHandler({
    required TenantValidationService tenantValidator,
    required RuleStudioCommandService commandService,
    required RbacService rbac,
    required IDateTimeProvider clock,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService,
       _rbac = rbac,
       _clock = clock;

  /// Returns the UUID of the newly created rule version.
  ///
  /// Throws [DomainException] if:
  /// - Caller lacks [UserPermission.canEditSlaRules]
  /// - [newConfig] is missing required keys for the given [ruleType]
  Future<String> handle(UpdateContractualRuleCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC — before any I/O
    if (!_rbac.can(command.callerRole, UserPermission.canEditSlaRules)) {
      throw const DomainException('Unauthorized: canEditSlaRules required.');
    }

    // 2. Validate config keys match engine contract (mirrors DB constraint)
    _validateConfig(command);

    // INV-10 / Sprint B: Guarda de backdating no application layer
    final now = _clock.nowUtc();
    final fiveMinsAgo = now.subtract(const Duration(minutes: 5));
    if (command.effectiveAtUtc.isBefore(fiveMinsAgo)) {
      throw const IntegrityException(
        'Anti-backdating violation: effective_at_utc is too far in the past',
        field: 'effectiveAtUtc',
      );
    }

    // 3. Atomic close + insert via RPC (atomicity guaranteed by Postgres)
    return _commandService.updateRule(
      contractId: command.contractId,
      oldRuleId: command.oldRuleId,
      ruleType: command.ruleType,
      newConfig: command.newConfig,
      evaluationOrder: command.evaluationOrder,
      effectiveAtUtc: command.effectiveAtUtc,
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
      'REQUIRED_EVIDENCE' => 'types',
      _ => throw DomainException('Unknown rule type: ${type.value}'),
    };

    if (!config.containsKey(requiredKey)) {
      throw DomainException(
        'Rule config for ${type.value} must contain key "$requiredKey".',
      );
    }
  }
}
