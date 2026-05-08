import 'package:uuid/uuid.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/contractor.dart';
import 'package:veraprob/domain/sla_audit/contractor_repository.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'save_contractor_command.dart';

/// Application handler for creating or updating a contractor.
///
/// RBAC: Requires [UserPermission.canManageContractors].
class SaveContractorHandler {
  final TenantValidationService _tenantValidator;
  final ContractorRepository _repository;
  final IDateTimeProvider _clock;
  final RbacService _rbac = RbacService();
  final _uuid = const Uuid();

  SaveContractorHandler({
    required TenantValidationService tenantValidator,
    required ContractorRepository repository,
    required IDateTimeProvider clock,
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _clock = clock;

  Future<Contractor> handle(SaveContractorCommand command) async {
    // â”€â”€ Step 1: INV-1 Fail-Fast Identity Sync â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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

    // 2. Prepare aggregate (reuse ID if provided for update, else generate new UUID)
    Contractor contractor;

    if (command.id != null) {
      final existing = await _repository.findById(
        command.organizationId,
        command.id!,
      );
      if (existing == null) {
        throw DomainException('Contractor not found: ${command.id}');
      }
      contractor = existing.copyWith(
        name: command.name,
        taxId: command.taxId,
        primaryEmail: command.primaryEmail,
        contactName: command.contactName,
      );
    } else {
      contractor = Contractor(
        id: _uuid.v4(),
        organizationId: command.organizationId,
        name: command.name,
        taxId: command.taxId,
        primaryEmail: command.primaryEmail,
        contactName: command.contactName,
        createdAtUtc: _clock.nowUtc(),
      );
    }

    // 3. Persist (Repository handles upsert)
    await _repository.save(contractor);
    return contractor;
  }
}
