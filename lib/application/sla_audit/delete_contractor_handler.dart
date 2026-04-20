import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'delete_contractor_command.dart';

/// Application handler for deleting a contractor.
///
/// RBAC: Requires [UserPermission.canManageContractors].
class DeleteContractorHandler {
  final TenantValidationService _tenantValidator;
  final ContractorRepository _repository;
  final RbacService _rbac = RbacService();

  DeleteContractorHandler({
    required TenantValidationService tenantValidator,
    required ContractorRepository repository,
  }) : _tenantValidator = tenantValidator,
       _repository = repository;

  Future<void> handle(DeleteContractorCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync ────────────────────────────
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // 2. RBAC check
    if (!_rbac.can(command.callerRole, UserPermission.canManageContractors)) {
      throw DomainException(
        'Unauthorized: Caller identifies as ${command.callerRole} but needs canManageContractors permission',
      );
    }

    // 2. Delegate to repository
    await _repository.delete(command.organizationId, command.contractorId);
  }
}
