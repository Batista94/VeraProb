import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
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

    // 3. Perform Field-Level Permission Check (INV-9 / INV-19)
    // Tenant Admins (admin role) CANNOT change SLA-critical fields.
    final changingSlaFields =
        command.name != null ||
        command.timezone != null ||
        command.currencyCode != null;

    if (changingSlaFields && command.callerRole != UserRole.superAdmin) {
      throw DomainException(
        'Forensic Violation: Role ${command.callerRole} cannot modify SLA-critical fields '
        '(Organization Name, Timezone, Currency). Only SuperAdmin can perform these changes.',
      );
    }

    // 4. Apply changes (only if fields are provided)
    final updatedOrg = org.copyWith(
      name: command.name ?? org.name,
      timezone: command.timezone ?? org.timezone,
      currencyCode: command.currencyCode ?? org.currencyCode,
      logoUrl:
          command.logoUrl, // Always allow logo change if authorized to handle
    );

    // 5. Persist
    await _repository.update(updatedOrg);
  }
}
