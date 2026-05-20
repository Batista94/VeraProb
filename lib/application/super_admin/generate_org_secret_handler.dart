import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';

/// Application handler for generating per-org HMAC secrets (INV-28).
///
/// Calls the `generate-org-secret` Edge Function which:
/// 1. Generates a 256-bit cryptographic secret
/// 2. Stores only the SHA-256 hash in org_api_secrets
/// 3. Returns the plain-text secret ONCE
///
/// The caller must display the secret to the user immediately.
/// After this call, the plain-text is irrecoverable.
class GenerateOrgSecretHandler {
  final SupabaseClient _client;
  final TenantValidationService _tenantValidator; // pr_scanner: INV-1

  GenerateOrgSecretHandler(
    this._client, {
    required TenantValidationService tenantValidator,
  }) : _tenantValidator = tenantValidator;

  /// Returns the plain-text secret (64-hex chars, 256 bits).
  /// Throws [OrgSecretException] on failure.
  Future<GenerateOrgSecretResult> handle({
    required String organizationId,
    required String sessionId,
  }) async {
    // ── INV-1: Validate caller session
    await _tenantValidator.assertTenantMatches(
      payloadOrgId: organizationId,
      sessionId: sessionId,
    );

    try {
      final data = await _invokeEdgeFunction(organizationId);
      return _parseSuccessResponse(data);
    } on FunctionException catch (e) {
      throw OrgSecretException('Falha ao gerar secret: ${_sanitizeDetails(e)}');
    } on OrgSecretException {
      rethrow;
    } on Exception catch (_) {
      throw const OrgSecretException(
        'Falha ao gerar secret: erro inesperado no mapeamento da resposta',
      );
    }
  }

  Future<Map<String, dynamic>> _invokeEdgeFunction(
    String organizationId,
  ) async {
    final response = await _client.functions.invoke(
      'generate-org-secret',
      body: {'organization_id': organizationId},
    );

    if (response.status != 200) {
      final body = response.data as Map<String, dynamic>?;
      final error = body?['error'] as String? ?? 'Unknown error';
      throw OrgSecretException('Falha ao gerar secret: $error');
    }

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw const OrgSecretException(
        'Falha ao gerar secret: resposta inválida do servidor',
      );
    }
    return data;
  }

  GenerateOrgSecretResult _parseSuccessResponse(Map<String, dynamic> data) {
    final secret = data['secret'];
    final version = data['version'];
    final orgId = data['organization_id'];

    if (secret is! String || version is! int || orgId is! String) {
      throw const OrgSecretException(
        'Falha ao gerar secret: campos obrigatórios ausentes ou inválidos',
      );
    }

    return GenerateOrgSecretResult(
      secret: secret,
      version: version,
      organizationId: orgId,
    );
  }

  // Sanitize FunctionException details: only forward String details to avoid
  // leaking internal Map/List structures that may contain sensitive data.
  String _sanitizeDetails(FunctionException e) {
    final details = e.details;
    if (details is String && details.isNotEmpty) return details;
    return e.reasonPhrase ?? 'erro desconhecido';
  }
}

/// Result of a successful secret generation.
class GenerateOrgSecretResult {
  final String secret;
  final int version;
  final String organizationId;

  const GenerateOrgSecretResult({
    required this.secret,
    required this.version,
    required this.organizationId,
  });
}

/// Application-layer exception for HMAC secret generation failures (INV-28).
class OrgSecretException extends DomainException {
  const OrgSecretException(super.message);
}
