import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Handler for revoking an active impersonation session (Stage E).
class RevokeImpersonationHandler {
  final SupabaseClient _client;
  final TenantValidationService _tenantValidator; // pr_scanner: INV-1

  RevokeImpersonationHandler(
    this._client, {
    required TenantValidationService tenantValidator,
  }) : _tenantValidator = tenantValidator;

  Future<void> handle({
    required String impersonationSessionId,
    required String targetOrgId,
    required String callerSessionId,
    String? reason,
  }) async {
    // ── INV-1: Validate caller session
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: targetOrgId,
      sessionId: callerSessionId,
    );

    try {
      final response = await _client.functions.invoke(
        'revoke-impersonation',
        body: {
          'session_id': impersonationSessionId,
          // ignore: use_null_aware_elements
          if (reason != null) 'reason': reason,
        },
      );

      if (response.status == 404) {
        throw const DomainException('Sessão não encontrada.');
      }
      if (response.status == 409) {
        throw const DomainException('Sessão já foi revogada.');
      }
      if (response.status != 200) {
        final data = response.data as Map<String, dynamic>?;
        throw DomainException(
          data?['error'] as String? ?? 'Falha ao revogar sessão.',
        );
      }
    } on FunctionException catch (e) {
      throw DomainException(
        'Falha ao revogar sessão: ${e.details ?? e.reasonPhrase}',
      );
    }
  }
}
