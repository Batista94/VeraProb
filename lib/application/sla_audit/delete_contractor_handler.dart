import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/contractor_repository.dart';
import 'delete_contractor_command.dart';

/// Application handler for deleting a contractor.
///
/// RBAC: Requires [UserPermission.canManageContractors].
class DeleteContractorHandler {
  final ContractorRepository _repository;
  final RbacService _rbac = RbacService();

  DeleteContractorHandler({required ContractorRepository repository})
    : _repository = repository;

  Future<void> handle(DeleteContractorCommand command) async {
    // 1. RBAC check
    if (!_rbac.can(command.callerRole, UserPermission.canManageContractors)) {
      throw Exception(
        'Unauthorized: Caller identifies as ${command.callerRole} but needs canManageContractors permission',
      );
    }

    // 2. Delegate to repository
    await _repository.delete(command.organizationId, command.contractorId);
  }
}
