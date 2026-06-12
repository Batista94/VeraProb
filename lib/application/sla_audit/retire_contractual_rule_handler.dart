import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'rule_studio_command_service.dart';

class RetireContractualRuleCommand {
  final String organizationId;
  final String ruleId;
  final UserRole callerRole;
  final String sessionId;

  const RetireContractualRuleCommand({
    required this.organizationId,
    required this.ruleId,
    required this.callerRole,
    required this.sessionId,
  });
}

class RetireContractualRuleHandler {
  final TenantValidationService _tenantValidator;
  final RuleStudioCommandService _commandService;
  final RbacService _rbac;

  RetireContractualRuleHandler({
    required TenantValidationService tenantValidator,
    required RuleStudioCommandService commandService,
    required RbacService rbac,
  }) : _tenantValidator = tenantValidator,
       _commandService = commandService,
       _rbac = rbac;

  Future<void> handle(RetireContractualRuleCommand command) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    if (!_rbac.can(command.callerRole, UserPermission.canEditSlaRules)) {
      throw const DomainException('Unauthorized: canEditSlaRules required.');
    }

    await _commandService.retireRule(ruleId: command.ruleId);
  }
}
