import '../../domain/admin/organization_repository.dart';
import '../../domain/enums/user_permissions.dart';
import '../../domain/services/rbac_service.dart';
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
      throw Exception(
        'Unauthorized: Caller identifies as ${command.callerRole} but needs canManageOrganization permission',
      );
    }

    // 2. Fetch aggregate
    final org = await _repository.findById(command.organizationId);
    if (org == null) {
      throw Exception('Organization not found: ${command.organizationId}');
    }

    // 3. Apply changes (value object with copyWith)
    final updatedOrg = org.copyWith(
      name: command.name,
      timezone: command.timezone,
      currencyCode: command.currencyCode,
      logoUrl: command.logoUrl,
    );

    // 4. Persist
    await _repository.update(updatedOrg);
  }
}
