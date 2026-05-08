import 'package:veraprob/application/shared/tenant_validation_service.dart';

/// Bypass tenant validator for SuperAdmin cross-tenant operations.
///
/// SuperAdmin JWT carries `super_admin: true` with null `org_id` — there is
/// no tenant session to validate against. This validator satisfies the
/// structural INV-1 contract (every handler calls `assertTenantMatches`)
/// while correctly being a no-op for the SuperAdmin context.
///
/// Used by: ArchiveOrganizationHandler, UpdateOrganizationQuotaHandler,
/// CreateOrganizationHandler, and any future SuperAdmin handler.
class SuperAdminBypassTenantValidator implements TenantValidationService {
  const SuperAdminBypassTenantValidator();

  @override
  Future<void> assertTenantMatches({
    required String payloadOrgId,
    required String sessionId,
  }) async {
    // No-op: SuperAdmin has sovereignty over all orgs.
  }

  @override
  void verifySourceOwnership({
    required String resourceOrgId,
    required String requesterOrgId,
    String? resourceType,
    String? resourceId,
  }) {
    // No-op: SuperAdmin owns all resources.
  }
}
