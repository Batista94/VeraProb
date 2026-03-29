import '../../domain/admin/organization_repository.dart';
import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
import '../../domain/sla_audit/domain_exception.dart';
import 'update_org_settings_command.dart';

/// Application handler for updating organization settings.
///
/// RBAC: Requires [UserPermission.canManageOrganization].
class UpdateOrgSettingsHandler {
  final OrganizationRepository _repository;
  final RbacService _rbac = RbacService();

  UpdateOrgSettingsHandler({required OrganizationRepository repository})
    : _repository = repository;

  Future<void> handle(UpdateOrgSettingsCommand command) async {
    // 1. RBAC check
    if (!_rbac.can(command.callerRole, UserPermission.canManageOrganization)) {
      throw DomainException(
        'Unauthorized: Caller identifies as ${command.callerRole} but needs canManageOrganization permission',
      );
    }

    // 2. Fetch aggregate
    final org = await _repository.findById(command.organizationId);
    if (org == null) {
      throw DomainException(
        'Organization not found: ${command.organizationId}',
      );
    }

    // 3. Apply changes (only if fields are provided)
    final updatedOrg = org.copyWith(
      name: command.name ?? org.name,
      timezone: command.timezone ?? org.timezone,
      currencyCode: command.currencyCode ?? org.currencyCode,
      logoUrl: command.logoUrl ?? org.logoUrl,
    );

    // 4. Persist
    await _repository.update(updatedOrg);
  }
}
