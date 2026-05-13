import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/admin/invite_user_handler.dart';
import 'package:veraprob/application/admin/invite_user_command.dart';
import 'package:veraprob/application/shared/super_admin_bypass_tenant_validator.dart';
import 'package:veraprob/core/utils/cnpj_validator.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/application/shared/app_types.dart';
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
  final RbacService _rbac = RbacService();

  CreateOrganizationHandler(
    this._repository,
    this._authenticatedClient,
    this._dateTimeProvider,
  );

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
    if (cmd.adminEmails.isEmpty) {
      throw const DomainException(
        'Pelo menos um e-mail de admin e obrigatorio.',
      );
    }
    for (final email in cmd.adminEmails) {
      final trimmed = email.trim().toLowerCase();
      if (trimmed.isEmpty || !trimmed.contains('@')) {
        throw DomainException('E-mail invalido: $email');
      }
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

    // 4c. billingDay must be 1–28 if provided (defense-in-depth; form data validates first)
    if (cmd.billingDay != null &&
        (cmd.billingDay! < 1 || cmd.billingDay! > 28)) {
      throw const DomainException('Dia de faturamento deve ser entre 1 e 28.');
    }

    // 4d. externalId length cap (defense-in-depth)
    if (cmd.externalId != null && cmd.externalId!.length > 100) {
      throw const DomainException(
        'ID externo não pode exceder 100 caracteres.',
      );
    }

    // 4e. Field contamination guard (INV-10: no silent failures)
    // Detects when form controller values leak across fields — a known
    // Flutter Stepper widget reconciliation edge case.
    if (cmd.legalName.contains(cmd.tradeName) &&
        cmd.legalName != cmd.tradeName &&
        cmd.legalName.length > cmd.tradeName.length) {
      throw const DomainException(
        'Dados corrompidos: legal_name contém trade_name. '
        'Limpe o formulário e tente novamente.',
      );
    }
    if (cmd.maxVehicles != null && cmd.maxVehicles! > 10000) {
      throw DomainException(
        'max_vehicles inválido (${cmd.maxVehicles}). Máximo permitido: 10.000.',
      );
    }
    if (cmd.maxActiveContracts != null && cmd.maxActiveContracts! > 5000) {
      throw DomainException(
        'max_active_contracts inválido (${cmd.maxActiveContracts}). '
        'Máximo permitido: 5.000.',
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
            adminEmails: cmd.adminEmails,
            superAdminUserId: cmd.superAdminUserId,
            capabilities: cmd.capabilities,
            toolCostCents: cmd.toolCostCents,
            dwellTimeSeconds: cmd.dwellTimeSeconds,
            reason: cmd.reason,
            billingDay: cmd.billingDay,
            contactEmail: cmd.contactEmail,
            externalId: cmd.externalId,
            organizationType: cmd.organizationType,
            allowedDomains: cmd.allowedDomains,
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

    // 7. Invite admins via SuperAdminInvitationCommandService (D4: bypasses TENANT_ADMIN check)
    //    IDs generated in Dart by InviteUserHandler — satisfies INV-7.
    final invitationService = SuperAdminInvitationCommandService(
      _authenticatedClient,
      orgId: orgId,
      superAdminUserId: cmd.superAdminUserId,
    );
    final inviteHandler = InviteUserHandler(
      tenantValidator: const SuperAdminBypassTenantValidator(),
      commandService: invitationService,
      dateTimeProvider: _dateTimeProvider,
    );

    final tokens = <String>[];
    for (final adminEmail in cmd.adminEmails) {
      final token = await inviteHandler.handle(
        InviteUserCommand(
          organizationId: orgId,
          callerRole: UserRole.superAdmin,
          invitedByUserId: cmd.superAdminUserId,
          email: adminEmail.trim().toLowerCase(),
          roleToAssign: UserRole.admin,
          sessionId: '',
        ),
      );
      tokens.add(token);
    }

    // 8. Generate org API secret (INV-28) — one-time plain-text, silent on failure
    String? orgApiSecret;
    try {
      final secretResponse = await _authenticatedClient.functions.invoke(
        'generate-org-secret',
        body: {'organization_id': orgId},
      );
      orgApiSecret = secretResponse.data?['secret'] as String?;
    } catch (_) {
      // Silent degradation — wizard shows a warning if secret is null.
    }

    // 9. Return immutable result
    return CreateOrganizationResult(
      orgId: orgId,
      invitationTokens: tokens,
      orgApiSecret: orgApiSecret,
    );
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
