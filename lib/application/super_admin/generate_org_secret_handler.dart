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
        throw DomainException('Falha ao gerar secret: $error');
      }

      final data = response.data as Map<String, dynamic>;
      return GenerateOrgSecretResult(
        secret: data['secret'] as String,
        version: data['version'] as int,
        organizationId: data['organization_id'] as String,
      );
    } on FunctionException catch (e) {
      throw DomainException(
        'Falha ao gerar secret: ${e.details ?? e.reasonPhrase}',
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
