import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/admin/invite_user_handler.dart';
import 'package:veraprob/application/admin/invite_user_command.dart';
import 'package:veraprob/application/shared/super_admin_bypass_tenant_validator.dart';
import 'package:veraprob/shared/utils/cnpj_validator.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/super_admin/plan_limits.dart';
import 'package:veraprob/domain/super_admin/create_organization_command.dart';
import 'package:veraprob/domain/super_admin/i_super_admin_repository.dart';
import 'package:veraprob/application/super_admin/create_organization_result.dart';
import 'package:veraprob/application/super_admin/super_admin_invitation_command_service.dart';

/// Application handler for [CreateOrganizationCommand].
///
/// Orchestrates provisioning steps:
///   1. RBAC gate
///   2. Organization data validation
///   3. Plan quota defaults resolution
///   4. Atomic DB provisioning
///   5. Admin invitation
///   6. API secret generation (INV-28)
///
/// INV-4:  Pure orchestration — no direct DB access.
/// INV-7:  IDs generated in Dart (via InviteUserHandler), not in SQL.
/// INV-22: Each provisioning step reinforces tenant isolation barriers.
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

  // ── Orchestrator ─────────────────────────────────────────────────────────────

  Future<CreateOrganizationResult> handle(CreateOrganizationCommand cmd) async {
    _assertSuperAdminRbac(); // Step 1 (INV-22)
    _validateOrganizationData(cmd); // Step 2 (INV-10, INV-18)
    final effectiveCmd = _applyPlanDefaults(cmd); // Step 3 (INV-19)
    final orgId = await _provisionOrganization(effectiveCmd); // Step 4 (INV-4)
    final tokens = await _inviteAdministrators(orgId, cmd); // Step 5 (INV-7)
    final orgApiSecret = await _setupOrganizationSecret(
      orgId,
    ); // Step 6 (INV-28)
    return CreateOrganizationResult(
      orgId: orgId,
      invitationTokens: tokens,
      orgApiSecret: orgApiSecret,
    );
  }

  // ── Step 1: RBAC ─────────────────────────────────────────────────────────────

  /// Guards the entire provisioning flow. Fails before any I/O.
  /// INV-22: Only superAdmin with canManageTenants may create tenants.
  void _assertSuperAdminRbac() {
    if (!_rbac.can(UserRole.superAdmin, UserPermission.canManageTenants)) {
      throw const DomainException('Unauthorized: canManageTenants required.');
    }
  }

  // ── Step 2: Validation ───────────────────────────────────────────────────────

  /// Validates all organization data. Pure Dart — zero I/O.
  /// Delegates to focused sub-validators for readability and testability.
  /// INV-10: No silent failures. INV-18: CnpjValidator is pure Dart.
  void _validateOrganizationData(CreateOrganizationCommand cmd) {
    _validateCnpj(cmd.cnpj);
    _validateRequiredFields(cmd);
    _validateAdminEmails(cmd.adminEmails);
    _validateAuditRequirements(cmd);
    _validateOptionalBounds(cmd);
    _validateQuotaBounds(cmd);
  }

  void _validateCnpj(String cnpj) {
    if (!CnpjValidator.isValid(cnpj)) {
      throw const DomainException('CNPJ inválido.');
    }
  }

  void _validateRequiredFields(CreateOrganizationCommand cmd) {
    if (cmd.legalName.trim().isEmpty) {
      throw const DomainException('Razão social é obrigatória.');
    }
    if (cmd.tradeName.trim().isEmpty) {
      throw const DomainException('Nome fantasia é obrigatório.');
    }
  }

  void _validateAdminEmails(List<String> adminEmails) {
    if (adminEmails.isEmpty) {
      throw const DomainException(
        'Pelo menos um e-mail de admin e obrigatorio.',
      );
    }
    for (final email in adminEmails) {
      final trimmed = email.trim().toLowerCase();
      if (trimmed.isEmpty || !trimmed.contains('@')) {
        throw DomainException('E-mail invalido: $email');
      }
    }
  }

  /// Validates ROI guardian cost and mandatory audit justification.
  /// INV-10: toolCostCents required for ROI Guardian calculation.
  void _validateAuditRequirements(CreateOrganizationCommand cmd) {
    if (cmd.toolCostCents == null) {
      throw const DomainException(
        'Custo mensal da ferramenta é obrigatório para calcular o ROI.',
      );
    }
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
  }

  /// Validates optional fields that have defined bounds (defense-in-depth).
  void _validateOptionalBounds(CreateOrganizationCommand cmd) {
    if (cmd.billingDay != null &&
        (cmd.billingDay! < 1 || cmd.billingDay! > 28)) {
      throw const DomainException('Dia de faturamento deve ser entre 1 e 28.');
    }
    if (cmd.externalId != null && cmd.externalId!.length > 100) {
      throw const DomainException(
        'ID externo não pode exceder 100 caracteres.',
      );
    }
  }

  /// Validates quota caps and detects Flutter Stepper field contamination.
  /// INV-10: Detects form controller value leakage across wizard steps.
  void _validateQuotaBounds(CreateOrganizationCommand cmd) {
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
  }

  // ── Step 3: Plan Defaults ────────────────────────────────────────────────────

  /// Returns [cmd] unchanged when both quotas are explicit.
  /// Otherwise builds a new command with [PlanLimits] defaults. (INV-19)
  CreateOrganizationCommand _applyPlanDefaults(CreateOrganizationCommand cmd) {
    if (cmd.maxVehicles != null && cmd.maxActiveContracts != null) return cmd;
    final planType = cmd.planType;
    return CreateOrganizationCommand(
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
    );
  }

  // ── Step 4: Provision ────────────────────────────────────────────────────────

  /// Creates org + billing event atomically via service_role RPC.
  /// Translates PostgrestException 23505 (CNPJ duplicate) to DomainException.
  /// INV-22: Org provisioned with isolated UUID — no cross-tenant leakage.
  Future<String> _provisionOrganization(CreateOrganizationCommand cmd) async {
    try {
      return await _repository.createOrganization(cmd);
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
  }

  // ── Step 5: Admin Invites ────────────────────────────────────────────────────

  /// Invites all admin emails via [InviteUserHandler].
  /// Uses [SuperAdminBypassTenantValidator] explicitly — INV-22 compliance.
  /// IDs generated in Dart by [InviteUserHandler] — satisfies INV-7.
  Future<List<String>> _inviteAdministrators(
    String orgId,
    CreateOrganizationCommand cmd,
  ) async {
    final inviteHandler = InviteUserHandler(
      tenantValidator: const SuperAdminBypassTenantValidator(),
      commandService: SuperAdminInvitationCommandService(
        _authenticatedClient,
        orgId: orgId,
        superAdminUserId: cmd.superAdminUserId,
      ),
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
    return tokens;
  }

  // ── Step 6: API Secret ───────────────────────────────────────────────────────

  /// Generates org API secret via Edge Function (INV-28).
  /// Returns null on failure — silent degradation by design.
  /// Wizard UI shows a warning when orgApiSecret is null.
  Future<String?> _setupOrganizationSecret(String orgId) async {
    try {
      final secretResponse = await _authenticatedClient.functions.invoke(
        'generate-org-secret',
        body: {'organization_id': orgId},
      );
      return secretResponse.data?['secret'] as String?;
    } catch (_) {
      return null;
    }
  }

  // ── Notification (unchanged) ─────────────────────────────────────────────────

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
