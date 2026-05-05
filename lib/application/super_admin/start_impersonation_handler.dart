import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/enums/user_permissions.dart';
import 'package:veraprob/domain/enums/user_role.dart';
import 'package:veraprob/domain/services/rbac_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Handler for starting a SuperAdmin impersonation session (Stage E).
///
/// Validates RBAC, calls the Edge Function, and returns session metadata.
///
/// INV-1:  SuperAdmin cross-tenant — JWT super_admin claim validated by Edge Function.
/// INV-22: Impersonator with target_org=A cannot access org B data.
/// INV-26: Non-existent/deleted org → 404.
class StartImpersonationHandler {
  final SupabaseClient _client;
  final TenantValidationService _tenantValidator; // pr_scanner: INV-1
  final IDateTimeProvider _dateTimeProvider;
  final RbacService _rbac = RbacService();

  StartImpersonationHandler(
    this._client, {
    required TenantValidationService tenantValidator,
    required IDateTimeProvider dateTimeProvider,
  }) : _tenantValidator = tenantValidator,
       _dateTimeProvider = dateTimeProvider;

  Future<ImpersonationSessionInfo> handle({
    required String targetOrgId,
    required String ticketId,
    required String reason,
    required UserRole callerRole,
    required String sessionId,
  }) async {
    // ── INV-1: SuperAdmin cross-tenant — validate session is authentic
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: targetOrgId,
      sessionId: sessionId,
    );

    // ── RBAC check
    if (!_rbac.can(callerRole, UserPermission.canImpersonateTenant)) {
      throw const DomainException(
        'Unauthorized: canImpersonateTenant permission required.',
      );
    }

    // ── Validate inputs
    if (ticketId.trim().isEmpty) {
      throw const DomainException(
        'ticket_id é obrigatório para impersonation.',
      );
    }
    if (reason.trim().length < 10) {
      throw const DomainException(
        'Justificativa deve ter pelo menos 10 caracteres.',
      );
    }

    // ── Call Edge Function
    try {
      final response = await _client.functions.invoke(
        'issue-impersonation-jwt',
        body: {
          'target_org_id': targetOrgId,
          'ticket_id': ticketId.trim(),
          'reason': reason.trim(),
        },
      );

      if (response.status == 404) {
        throw const DomainException('Organização não encontrada.');
      }
      if (response.status == 409) {
        throw const DomainException(
          'Você já possui uma sessão de impersonation ativa. Revogue-a primeiro.',
        );
      }
      if (response.status != 200) {
        final data = response.data as Map<String, dynamic>?;
        throw DomainException(
          data?['error'] as String? ?? 'Falha ao iniciar impersonation.',
        );
      }

      try {
        final data = response.data as Map<String, dynamic>;
        return ImpersonationSessionInfo(
          sessionId: data['session_id'] as String,
          targetOrgId: data['target_org_id'] as String,
          targetOrgName: data['target_org_name'] as String,
          impersonatorId: data['impersonator_id'] as String,
          issuedAt: DateTime.parse(data['issued_at'] as String).toUtc(),
          expiresAt: DateTime.parse(data['expires_at'] as String).toUtc(),
          dateTimeProvider: _dateTimeProvider,
        );
      } catch (e) {
        throw DomainException('Resposta inválida da Edge Function: $e');
      }
    } on FunctionException catch (e) {
      throw DomainException(
        'Falha ao iniciar impersonation: ${e.details ?? e.reasonPhrase}',
      );
    }
  }
}

/// Metadata for an active impersonation session.
class ImpersonationSessionInfo {
  final String sessionId;
  final String targetOrgId;
  final String targetOrgName;
  final String impersonatorId;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final IDateTimeProvider _dateTimeProvider;

  const ImpersonationSessionInfo({
    required this.sessionId,
    required this.targetOrgId,
    required this.targetOrgName,
    required this.impersonatorId,
    required this.issuedAt,
    required this.expiresAt,
    required IDateTimeProvider dateTimeProvider,
  }) : _dateTimeProvider = dateTimeProvider;

  Duration get remainingDuration {
    final now = _dateTimeProvider.nowUtc();
    if (expiresAt.isBefore(now)) return Duration.zero;
    return expiresAt.difference(now);
  }

  bool get isExpired => remainingDuration == Duration.zero;
}
