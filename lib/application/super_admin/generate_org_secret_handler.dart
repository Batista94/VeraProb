import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/application/shared/tenant_validation_service.dart';

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
  /// Throws [DomainException] on failure.
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
      final response = await _client.functions.invoke(
        'generate-org-secret',
        body: {'organization_id': organizationId},
      );

      if (response.status != 200) {
        final data = response.data as Map<String, dynamic>?;
        final error = data?['error'] as String? ?? 'Unknown error';
        throw OrgSecretException('Falha ao gerar secret: $error');
      }

      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const OrgSecretException(
          'Falha ao gerar secret: resposta inválida do servidor',
        );
      }

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
    } on FunctionException catch (e) {
      // Sanitize details: only use string details or reasonPhrase.
      // Complex objects (Map, List) may contain sensitive internal data.
      final details = e.details;
      final sanitized = details is String && details.isNotEmpty
          ? details
          : (e.reasonPhrase ?? 'erro desconhecido');
      throw OrgSecretException('Falha ao gerar secret: $sanitized');
    } on OrgSecretException {
      rethrow;
    } on Exception catch (_) {
      throw const OrgSecretException(
        'Falha ao gerar secret: erro inesperado no mapeamento da resposta',
      );
    }
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
class OrgSecretException implements Exception {
  final String message;

  const OrgSecretException(this.message);

  @override
  String toString() => 'OrgSecretException: $message';
}
