import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'update_org_settings_command.dart';

/// Application handler for updating organization settings.
///
/// RBAC: Requires [UserPermission.canManageOrganization].
/// Stage C: Governance changes require mandatory justification.
class UpdateOrgSettingsHandler {
  final TenantValidationService _tenantValidator;
  final OrganizationRepository _repository;
  final SystemAuditLogService? _auditLogService;
  final RbacService _rbac = RbacService();

  UpdateOrgSettingsHandler({
    required TenantValidationService tenantValidator,
    required OrganizationRepository repository,
    SystemAuditLogService? auditLogService,
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _auditLogService = auditLogService;

  Future<void> handle(UpdateOrgSettingsCommand command) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: command.organizationId,
      sessionId: command.sessionId,
    );

    // ── Step 2: RBAC check
    if (!_rbac.can(command.callerRole, UserPermission.canManageOrganization)) {
      throw DomainException(
        'Unauthorized: Caller identifies as ${command.callerRole} but needs canManageOrganization permission',
      );
    }

    // ── Step 3: Fetch aggregate
    final org = await _repository.findById(command.organizationId);
    if (org == null) {
      throw const DomainException('Organização não encontrada.');
    }

    // ── Step 4: Field-Level Permission Check (INV-9 / INV-19)
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

    // ── Step 5: Validate reason for governance changes (Stage C)
    final isGovernanceChange = command.capabilities != null;
    if (isGovernanceChange) {
      if (command.reason == null || command.reason!.trim().isEmpty) {
        throw const DomainException(
          'Justificativa obrigatória para mudanças de governança (capabilities).',
        );
      }
      if (command.reason!.trim().length < 10) {
        throw const DomainException(
          'Justificativa deve ter pelo menos 10 caracteres.',
        );
      }
    }

    // ── Step 6: Build old snapshot for audit
    final oldSnapshot = <String, Object?>{
      'name': org.name,
      'timezone': org.timezone,
      'currency_code': org.currencyCode,
      'logo_url': org.logoUrl,
      'organization_type': org.organizationType,
      'capabilities': org.capabilities.toJson(),
    };

    // ── Step 7: Apply changes
    final updatedOrg = org.copyWith(
      name: command.name ?? org.name,
      timezone: command.timezone ?? org.timezone,
      currencyCode: command.currencyCode ?? org.currencyCode,
      logoUrl: command.logoUrl,
      organizationType: command.organizationType ?? org.organizationType,
      capabilities: command.capabilities ?? org.capabilities,
    );

    // ── Step 8: Persist
    await _repository.update(updatedOrg);

    // ── Step 9: Log governance change (Stage C)
    if (isGovernanceChange && _auditLogService != null) {
      final newSnapshot = <String, Object?>{
        'name': updatedOrg.name,
        'timezone': updatedOrg.timezone,
        'currency_code': updatedOrg.currencyCode,
        'logo_url': updatedOrg.logoUrl,
        'organization_type': updatedOrg.organizationType,
        'capabilities': updatedOrg.capabilities.toJson(),
      };

      await _auditLogService.logGovernanceChange(
        eventType: 'LIMIT_CHANGE',
        reason: command.reason!,
        actorType: ActorType.human,
        organizationId: command.organizationId,
        organizationName: updatedOrg.name,
        oldSnapshot: oldSnapshot,
        newSnapshot: newSnapshot,
      );
    }
  }
}
