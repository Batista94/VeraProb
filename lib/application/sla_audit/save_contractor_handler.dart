import 'package:uuid/uuid.dart';
import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/contractor.dart';
import '../../domain/sla_audit/contractor_repository.dart';
import '../../domain/sla_audit/domain_exception.dart';
import 'save_contractor_command.dart';

/// Application handler for creating or updating a contractor.
///
/// RBAC: Requires [UserPermission.canManageContractors].
class SaveContractorHandler {
  final ContractorRepository _repository;
  final RbacService _rbac = RbacService();
  final _uuid = const Uuid();

  SaveContractorHandler({required ContractorRepository repository})
    : _repository = repository;

  Future<Contractor> handle(SaveContractorCommand command) async {
    // 1. RBAC check
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
        createdAtUtc: DateTime.now().toUtc(),
      );
    }

    // 3. Persist (Repository handles upsert)
    await _repository.save(contractor);
    return contractor;
  }
}
