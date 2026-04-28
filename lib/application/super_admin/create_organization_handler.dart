import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/admin/invite_user_handler.dart';
import 'package:veraprob/application/admin/invite_user_command.dart';
import 'package:veraprob/application/audit/system_audit_log_service.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/cnpj_validator.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/admin/actor_type.dart';
import 'package:veraprob/domain/super_admin/plan_limits.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/application/super_admin/create_organization_result.dart';
import 'package:veraprob/application/super_admin/super_admin_invitation_command_service.dart';

/// Application handler for [CreateOrganizationCommand].
///
/// Orchestrates: RBAC → validation → org creation → billing event → admin invite.
///
/// INV-4: Pure orchestration — no direct DB access.
/// INV-7: IDs generated in Dart (via InviteUserHandler), not in SQL.
class CreateOrganizationHandler {
  final ISuperAdminRepository _repository;
  final SupabaseClient _authenticatedClient;
  final IDateTimeProvider _dateTimeProvider;
  final SystemAuditLogService? _auditLogService;
  final RbacService _rbac = RbacService();

  CreateOrganizationHandler(
    this._repository,
    this._authenticatedClient,
    this._dateTimeProvider, {
    SystemAuditLogService? auditLogService,
  }) : _auditLogService = auditLogService;

  Future<CreateOrganizationResult> handle(CreateOrganizationCommand cmd) async {
    // 1. RBAC — before any I/O
    if (!_rbac.can(UserRole.superAdmin, UserPermission.canManageTenants)) {
      throw const DomainException('Unauthorized: canManageTenants required.');
    }

    // 2. CNPJ validation — modulo-11 check-digit (INV-18: CnpjValidator is pure Dart)
    if (!CnpjValidator.isValid(cmd.cnpj)) {
      throw const DomainException('CNPJ inválido.');
    }

    // 3. Required fields validation
    if (cmd.legalName.trim().isEmpty) {
      throw const DomainException('Razão social é obrigatória.');
    }
    if (cmd.tradeName.trim().isEmpty) {
      throw const DomainException('Nome fantasia é obrigatório.');
    }

    // 4. Email validation
    final email = cmd.initialAdminEmail.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      throw const DomainException('E-mail inválido.');
    }

    // 4a. tool_cost_cents required — ROI Guardian cannot function without it (INV-10)
    if (cmd.toolCostCents == null) {
      throw const DomainException(
        'Custo mensal da ferramenta é obrigatório para calcular o ROI.',
      );
    }

    // 4b. reason required — every ORG_CREATED must have a justification in the audit log.
    if (cmd.reason == null || cmd.reason!.trim().isEmpty) {
      throw const DomainException(
        'Justificativa de criação é obrigatória para o log de auditoria.',
      );
    }
    if (cmd.reason!.trim().length < 10) {
      throw const DomainException(
        'Justificativa deve ter pelo menos 10 caracteres.',
      );
    }

    // 5. Auto-fill quota limits from PlanLimits defaults when not explicitly provided
    final planType = cmd.planType;
    final effectiveCmd =
        (cmd.maxVehicles == null || cmd.maxActiveContracts == null)
        ? CreateOrganizationCommand(
            legalName: cmd.legalName,
            tradeName: cmd.tradeName,
            cnpj: cmd.cnpj,
            timezone: cmd.timezone,
            currencyCode: cmd.currencyCode,
            planType: cmd.planType,
            maxVehicles: cmd.maxVehicles ?? PlanLimits.maxVehicles(planType),
            maxActiveContracts:
                cmd.maxActiveContracts ?? PlanLimits.maxContracts(planType),
            initialAdminEmail: cmd.initialAdminEmail,
            superAdminUserId: cmd.superAdminUserId,
            capabilities: cmd.capabilities,
            toolCostCents: cmd.toolCostCents,
            dwellTimeSeconds: cmd.dwellTimeSeconds,
            reason: cmd.reason,
          )
        : cmd;

    // 6. Create org + billing event (atomic RPC via service_role)
    late final String orgId;
    try {
      orgId = await _repository.createOrganization(effectiveCmd);
    } on PostgrestException catch (e) {
      if (e.code == '23505' &&
          (e.message.contains('cnpj') ||
              e.details.toString().contains('cnpj'))) {
        throw const DomainException(
          'Já existe uma organização cadastrada com este CNPJ.',
        );
      }
      rethrow;
    }

    // 7. Invite first admin via SuperAdminInvitationCommandService (D4: bypasses TENANT_ADMIN check)
    //    IDs generated in Dart by InviteUserHandler — satisfies INV-7.
    final invitationService = SuperAdminInvitationCommandService(
      _authenticatedClient,
      orgId: orgId,
      superAdminUserId: cmd.superAdminUserId,
    );
    // Super-admin context: use a bypass tenant validator that always passes
    final inviteHandler = InviteUserHandler(
      tenantValidator: const _BypassTenantValidator(),
      commandService: invitationService,
      dateTimeProvider: _dateTimeProvider,
    );

    final token = await inviteHandler.handle(
      InviteUserCommand(
        organizationId: orgId,
        callerRole: UserRole.superAdmin,
        invitedByUserId: cmd.superAdminUserId,
        email: email,
        roleToAssign: UserRole.admin,
        sessionId: '', // super-admin context — no regular session
      ),
    );

    // 8. Log ORG_CREATED governance event (INV-3: audit trail)
    if (_auditLogService != null) {
      await _auditLogService.logGovernanceChange(
        eventType: 'ORG_CREATED',
        reason: cmd.reason!.trim(),
        actorType: ActorType.human,
        organizationId: orgId,
        organizationName: effectiveCmd.tradeName,
        oldSnapshot: const <String, Object?>{},
        newSnapshot: <String, Object?>{
          'legal_name': effectiveCmd.legalName,
          'trade_name': effectiveCmd.tradeName,
          'cnpj': effectiveCmd.cnpj,
          'plan_type': effectiveCmd.planType.dbValue,
          'max_vehicles': effectiveCmd.maxVehicles,
          'max_active_contracts': effectiveCmd.maxActiveContracts,
          'dwell_time_seconds': effectiveCmd.dwellTimeSeconds,
        },
      );
    }

    // 9. Return immutable result
    return CreateOrganizationResult(orgId: orgId, invitationToken: token);
  }

  /// Fires the invite notification Edge Function — silent failure by design.
  ///
  /// The invite link shown in the success dialog is the fallback if this fails.
  Future<void> sendInviteNotification({
    required String email,
    required String inviteUrl,
    required String orgName,
  }) async {
    try {
      await _authenticatedClient.functions.invoke(
        'notify-invite',
        body: {'email': email, 'inviteUrl': inviteUrl, 'orgName': orgName},
      );
    } catch (_) {
      // Silent — the invite link in the dialog is the primary delivery path.
    }
  }
}

/// Bypass tenant validator for super-admin operations.
///
/// Super-admin creates organizations outside the normal tenant flow —
/// there is no JWT session with an organization_id to validate against.
class _BypassTenantValidator implements TenantValidationService {
  const _BypassTenantValidator();

  @override
  Future<void> assertTenantMatches({
    required String payloadOrgId,
    required String sessionId,
  }) async {
    // No-op: super-admin context has no tenant session to validate.
  }

  @override
  void verifySourceOwnership({
    required String resourceOrgId,
    required String requesterOrgId,
    String? resourceType,
    String? resourceId,
  }) {
    // No-op: super-admin owns all resources.
  }
}
