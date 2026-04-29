import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/org_status.dart';
import 'package:veraprob/domain/super_admin/archive_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';

/// Application handler for archiving a tenant organization.
///
/// Orchestrates: RBAC → validation → status guard → repo call.
///
/// INV-10: Throws [DomainException] for all guard violations.
/// INV-26: Archived and deleted orgs return identical errors to prevent org enumeration.
/// INV-3: Secrets revoked via revoked_at in RPC — never deleted.
class ArchiveOrganizationHandler {
  final ISuperAdminRepository _repository;
  final TenantValidationService _tenantValidator;
  final RbacService _rbac = RbacService();

  ArchiveOrganizationHandler({
    required ISuperAdminRepository repository,
    required TenantValidationService tenantValidator,
  }) : _repository = repository,
       _tenantValidator = tenantValidator;

  /// Convenience entry-point for UI callers that only have primitive values.
  ///
  /// Converts [currentStatusKey] (uppercase DB string) to [OrgStatus] then delegates
  /// to [handle]. Features do not need to import [OrgStatus] or [ArchiveOrganizationCommand].
  Future<void> handlePrimitives({
    required String orgId,
    required String reason,
    required String superAdminUserId,
    required String currentStatusKey,
    required String sessionId,
  }) {
    final currentStatus = OrgStatus.fromString(currentStatusKey.toLowerCase());
    return handle(
      ArchiveOrganizationCommand(
        orgId: orgId,
        reason: reason,
        superAdminUserId: superAdminUserId,
        currentStatus: currentStatus,
        sessionId: sessionId,
      ),
    );
  }

  Future<void> handle(ArchiveOrganizationCommand cmd) async {
    // 0. INV-1 Fail-Fast Identity Sync
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: cmd.orgId,
      sessionId: cmd.sessionId,
    );

    // 1. RBAC — before any I/O
    if (!_rbac.can(UserRole.superAdmin, UserPermission.canManageTenants)) {
      throw const DomainException('Unauthorized: canManageTenants required.');
    }

    // 2. Reason required and must be substantive (INV-10)
    final reason = cmd.reason.trim();
    if (reason.isEmpty) {
      throw const DomainException(
        'É necessário informar um motivo para arquivar a organização.',
      );
    }
    if (reason.length < 10) {
      throw const DomainException(
        'O motivo deve ter pelo menos 10 caracteres.',
      );
    }

    // 3. Status guard — fail-fast before network round-trip (INV-10)
    if (cmd.currentStatus == OrgStatus.archived) {
      throw const DomainException('Organização já está arquivada.');
    }
    if (cmd.currentStatus == OrgStatus.deleted) {
      // INV-26: same error shape as "not found" — prevents org status enumeration
      throw const DomainException('Organização não encontrada.');
    }

    // 4. Delegate to repo — RPC handles atomic status update + secret revocation
    await _repository.archiveOrganization(cmd);
  }
}
