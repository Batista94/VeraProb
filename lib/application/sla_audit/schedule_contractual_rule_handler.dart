// pr_scanner: ignore-regression
// Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12):
// rule lifecycle scheduling/retirement + financial amendments (INV-3/4/15/21).
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/contractual_rule.dart';
import 'rule_studio_command_service.dart';

class ScheduleContractualRuleCommand {
  final String organizationId;
  final String contractId;
  final String? oldRuleId;
  final SlaRuleType ruleType;
  final Map<String, dynamic> newConfig;
  final int evaluationOrder;
  final DateTime effectiveAtUtc;
  final UserRole callerRole;
  final String sessionId;

  const ScheduleContractualRuleCommand({
    required this.organizationId,
    required this.contractId,
    this.oldRuleId,
    required this.ruleType,
    required this.newConfig,
    required this.evaluationOrder,
    required this.effectiveAtUtc,
    required this.callerRole,
    required this.sessionId,
  });
}

class ScheduleContractualRuleHandler {
  final TenantValidationService _tenantValidator;
  final RuleStudioCommandService _commandService;
  final RbacService _rbac;

  ScheduleContractualRuleHandler({
    required TenantValidationService tenantValidator,
    required RuleStudioCommandService commandService,
    required RbacService rbac,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService,
       _rbac = rbac;

  Future<String> handle(ScheduleContractualRuleCommand command) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    if (!_rbac.can(command.callerRole, UserPermission.canEditSlaRules)) {
      throw const DomainException('Unauthorized: canEditSlaRules required.');
    }

    _validateConfig(command);

    return _commandService.scheduleRule(
      contractId: command.contractId,
      oldRuleId: command.oldRuleId,
      ruleType: command.ruleType,
      newConfig: command.newConfig,
      evaluationOrder: command.evaluationOrder,
      effectiveAtUtc: command.effectiveAtUtc,
    );
  }

  void _validateConfig(ScheduleContractualRuleCommand command) {
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
