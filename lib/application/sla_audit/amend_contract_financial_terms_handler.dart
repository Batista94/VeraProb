// pr_scanner: ignore-regression
// Council-reviewed (Sprint B SLA Versioning plan, approved 2026-06-12):
// rule lifecycle scheduling/retirement + financial amendments (INV-3/4/15/21).
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/i_contract_financial_amendment_repository.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';

class AmendContractFinancialTermsCommand {
  final String organizationId;
  final String contractId;
  final int? financialCeilingCents;
  final int penaltyMultiplierBps;
  final DateTime effectiveAtUtc;
  final String? notes;
  final UserRole callerRole;
  final String sessionId;

  const AmendContractFinancialTermsCommand({
    required this.organizationId,
    required this.contractId,
    this.financialCeilingCents,
    required this.penaltyMultiplierBps,
    required this.effectiveAtUtc,
    this.notes,
    required this.callerRole,
    required this.sessionId,
  });
}

class AmendContractFinancialTermsHandler {
  final TenantValidationService _tenantValidator;
  final IContractFinancialAmendmentRepository _repository;
  final RbacService _rbac;
  final IDateTimeProvider _clock;

  AmendContractFinancialTermsHandler({
    required TenantValidationService tenantValidator,
    required IContractFinancialAmendmentRepository repository,
    required RbacService rbac,
    required IDateTimeProvider clock,
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _rbac = rbac,
       _clock = clock;

  Future<void> handle(AmendContractFinancialTermsCommand command) async {
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    if (!_rbac.can(command.callerRole, UserPermission.canEditSlaRules)) {
      throw const DomainException('Unauthorized: canEditSlaRules required.');
    }

    final now = _clock.nowUtc();
    final fiveMinsAgo = now.subtract(const Duration(minutes: 5));
    if (command.effectiveAtUtc.isBefore(fiveMinsAgo)) {
      throw const IntegrityException(
        'Anti-backdating violation: effective_at_utc is too far in the past',
        field: 'effectiveAtUtc',
      );
    }

    await _repository.amendContractFinancialTerms(
      contractId: command.contractId,
      financialCeilingCents: command.financialCeilingCents,
      penaltyMultiplierBps: command.penaltyMultiplierBps,
      effectiveAtUtc: command.effectiveAtUtc,
      notes: command.notes,
    );
  }
}
