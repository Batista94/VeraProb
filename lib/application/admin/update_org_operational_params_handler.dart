import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/domain/admin/organization_repository.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'update_org_operational_params_command.dart';

/// Handler for updating operational parameters by org admin (Stage G).
///
/// Admin de org pode editar dwell_time_seconds e max_kinematic_speed_kmh.
/// Requires role >= admin. Logs changes to system_audit_log.
///
/// INV-1:  org_id filter ALL — fail-fast tenant validation.
/// INV-10: Domain validation for physical limits.
class UpdateOrgOperationalParamsHandler {
  final TenantValidationService _tenantValidator;
  final OrganizationRepository _repository;
  final SystemAuditLogService? _auditLogService;

  UpdateOrgOperationalParamsHandler({
    required TenantValidationService tenantValidator,
    required OrganizationRepository repository,
    SystemAuditLogService? auditLogService,
  }) : _tenantValidator = tenantValidator,
       _repository = repository,
       _auditLogService = auditLogService;

  Future<void> handle(UpdateOrgOperationalParamsCommand cmd) async {
    // ── Step 1: INV-1 Fail-Fast Identity Sync
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: cmd.organizationId,
      sessionId: cmd.sessionId,
    );

    // ── Step 2: RBAC — admin or superAdmin only
    if (cmd.callerRole != UserRole.admin &&
        cmd.callerRole != UserRole.superAdmin) {
      throw DomainException(
        'Unauthorized: Role ${cmd.callerRole} cannot modify operational parameters.',
      );
    }

    // ── Step 3: Validate reason
    if (cmd.reason.trim().isEmpty) {
      throw const DomainException(
        'Justificativa obrigatória para mudanças de parâmetros operacionais.',
      );
    }
    if (cmd.reason.trim().length < 10) {
      throw const DomainException(
        'Justificativa deve ter pelo menos 10 caracteres.',
      );
    }

    // ── Step 4: Validate domain constraints
    if (cmd.dwellTimeSeconds != null) {
      if (cmd.dwellTimeSeconds! < 60) {
        throw const DomainException('Tempo de parada mínimo é 60 segundos.');
      }
      if (cmd.dwellTimeSeconds! > 1800) {
        throw const DomainException(
          'Tempo de parada máximo é 1800 segundos (30 minutos).',
        );
      }
    }

    if (cmd.maxKinematicSpeedKmh != null) {
      if (cmd.maxKinematicSpeedKmh! <= 0) {
        throw const DomainException(
          'Velocidade máxima deve ser maior que zero.',
        );
      }
      if (cmd.maxKinematicSpeedKmh! > 200.0) {
        // Physical Metric - Double Required
        throw const DomainException(
          'Velocidade máxima não pode exceder 200 km/h (limite físico).',
        );
      }
    }

    // ── Step 5: Fetch current org
    final org = await _repository.findById(cmd.organizationId);
    if (org == null) {
      throw DomainException('Organization not found: ${cmd.organizationId}');
    }

    // ── Step 6: Build old snapshot
    final oldSnapshot = <String, Object?>{
      'dwell_time_seconds': org.dwellTimeSeconds,
      'max_kinematic_speed_kmh': org.capabilities.maxKinematicSpeedKmh,
    };

    // ── Step 7: Apply changes
    final updatedCapabilities = org.capabilities.copyWith(
      maxKinematicSpeedKmh: cmd.maxKinematicSpeedKmh,
    );

    final updatedOrg = org.copyWith(
      capabilities: updatedCapabilities,
      dwellTimeSeconds: cmd.dwellTimeSeconds,
    );

    // ── Step 8: Persist
    await _repository.update(updatedOrg);

    // ── Step 9: Log governance change
    if (_auditLogService != null) {
      final newSnapshot = <String, Object?>{
        'dwell_time_seconds': cmd.dwellTimeSeconds,
        'max_kinematic_speed_kmh': cmd.maxKinematicSpeedKmh,
      };

      await _auditLogService.logGovernanceChange(
        eventType: 'OPERATIONAL_PARAM_CHANGE',
        reason: cmd.reason.trim(),
        actorType: ActorType.human,
        organizationId: cmd.organizationId,
        organizationName: org.name,
        oldSnapshot: oldSnapshot,
        newSnapshot: newSnapshot,
      );
    }
  }
}
