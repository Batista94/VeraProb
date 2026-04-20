import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:veraprob/domain/shared/integrity_exception.dart';

/// IntegrityVerificationService — HMAC On-Read verification for financial data.
///
/// **INV-31 (HMAC Zero-Knowledge):**
/// Before ANY financial/ledger data is served to the application layer, this
/// service validates the HMAC signature by calling the Edge Function verifier.
///
/// **INV-10 (Error Visibility — Fail-Fast):**
/// If the Edge Function is unreachable (timeout, offline, network error), the
/// service **BLOCKS** the read and throws [IntegrityException]. There is NO
/// fallback to "serve unverified data". This is a deliberate design choice:
///
/// | Policy      | Behavior                                    | VeraProb? |
/// |-------------|---------------------------------------------|-----------|
/// | Fail-Safe   | Serve data without HMAC check on timeout    | ❌ NEVER  |
/// | Fail-Fast   | Throw IntegrityException on timeout         | ✅ YES    |
///
/// **Rationale:** A "degraded mode" that serves unverified financial data
/// recreates the exact fraud window that INV-31 eliminates. If an attacker
/// knows the verifier is offline, they can tamper with ledger entries and
/// the system would serve them as authentic.
///
/// **Usage:**
/// ```dart
/// final verifier = IntegrityVerificationService(
///   edgeFunctionUrl: 'https://<project>.supabase.co/functions/verify-ledger-hmac',
///   httpClient: http.Client(),
///   timeout: Duration(seconds: 10),
/// );
///
/// // Before returning ledger data to the UI:
/// await verifier.verifyHmac(
///   payload: {'amount_cents': 50000, 'organization_id': 'org-123'},
///   storedSignature: 'a1b2c3...',
///   recordId: 'ledger-entry-456',
/// );
/// // If this returns without throwing, the data is verified.
/// // If it throws, the read is BLOCKED.
/// ```
class IntegrityVerificationService {
  final String _edgeFunctionUrl;
  final http.Client _httpClient;
  final Duration _timeout;

  IntegrityVerificationService({
    required String edgeFunctionUrl,
    required http.Client httpClient,
    Duration timeout = const Duration(seconds: 10),
  }) : _edgeFunctionUrl = edgeFunctionUrl,
       _httpClient = httpClient,
       _timeout = timeout;

  /// Verifies the HMAC signature of a payload against the stored signature.
  ///
  /// **Flow:**
  /// 1. POST the canonical payload + stored signature to the Edge Function
  /// 2. Edge Function recomputes HMAC and compares
  /// 3. Returns normally if valid, throws [IntegrityException] if invalid
  ///
  /// **Fail-Fast on connectivity failure:**
  /// - Timeout → [IntegrityException] with reason `UNAVAILABLE`
  /// - HTTP error (5xx) → [IntegrityException] with reason `UNAVAILABLE`
  /// - HMAC mismatch → [IntegrityException] with reason `TAMPERED`
  ///
  /// @param canonicalPayload — Pre-sorted canonical JSON payload (from
  ///   `BasePostgresRepository.canonicalJson()`). Already sorted so the Edge
  ///   Function doesn't need to re-sort.
  /// @param storedSignature — The HMAC-SHA256 hex digest stored in the DB
  /// @param recordId — The database record ID for forensic logging
  /// @param recordType — The domain type (e.g., 'ledger_entry', 'financial_snapshot')
  ///
  /// @throws [IntegrityException] on ANY failure (Fail-Fast)
  Future<void> verifyHmac({
    required String canonicalPayload,
    required String storedSignature,
    required String recordId,
    required String recordType,
  }) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse(_edgeFunctionUrl),
            headers: {
              'Content-Type': 'application/json',
              'X-Record-Id': recordId,
              'X-Record-Type': recordType,
            },
            body: jsonEncode({
              'canonical_payload': canonicalPayload,
              'stored_signature': storedSignature,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        // Edge Function returns {"valid": true} or {"valid": false, "reason": "..."}
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final result = HmacVerificationResult.fromJson(body);

        if (result.valid) {
          return; // ✅ Verified — proceed with read
        }

        // ❌ HMAC mismatch — data has been tampered with
        throw IntegrityException(
          'HMAC verification FAILED for $recordType/$recordId: stored signature '
          'does not match recomputed signature. Data may have been tampered with. '
          'Edge Function reason: ${result.reason ?? "unknown"}',
          field: 'hmac_signature',
        );
      }

      if (response.statusCode >= 500) {
        // Edge Function infrastructure error — Fail-Fast
        throw IntegrityException(
          'HMAC verification service returned HTTP ${response.statusCode} '
          'for $recordType/$recordId. Cannot verify integrity. Read BLOCKED (Fail-Fast).',
          field: 'hmac_verification_service',
        );
      }

      // Unexpected response — Fail-Fast
      throw IntegrityException(
        'HMAC verification service returned unexpected HTTP ${response.statusCode} '
        'for $recordType/$recordId. Read BLOCKED (Fail-Fast).',
        field: 'hmac_verification_service',
      );
    } on IntegrityException {
      // Re-throw domain exceptions as-is (already have full forensic context)
      rethrow;
    } on http.ClientException catch (e) {
      // Network failure — Fail-Fast
      throw IntegrityException(
        'HMAC verification service unreachable for $recordType/$recordId: $e. '
        'Read BLOCKED (Fail-Fast).',
        field: 'hmac_verification_service',
      );
    } on TimeoutException catch (e) {
      // Timeout — Fail-Fast
      throw IntegrityException(
        'HMAC verification service timed out after ${_timeout.inSeconds}s '
        'for $recordType/$recordId: $e. Read BLOCKED (Fail-Fast).',
        field: 'hmac_verification_service',
      );
    }
  }
}

/// HMAC verification result — mirrors the Edge Function response.
class HmacVerificationResult {
  final bool valid;
  final String? reason;

  const HmacVerificationResult({required this.valid, this.reason});

  factory HmacVerificationResult.fromJson(Map<String, dynamic> json) {
    return HmacVerificationResult(
      valid: json['valid'] == true,
      reason: json['reason'] as String?,
    );
  }
}
