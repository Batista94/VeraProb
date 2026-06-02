import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

/// INV-26: Error Parity — Intercepts PostgREST/PostgreSQL-specific error
/// codes and maps them to domain-layer exceptions that produce indistinguishable
/// HTTP 404 responses.
///
/// **Security Contract:**
/// - Database error codes (22P02, PGRST116, etc.) MUST NOT leak to the client.
/// - All information-disclosure errors are mapped to [ResourceNotFoundException],
///   which the [SovereigntyErrorMapper] converts to `{"error":"Not Found"}` 404.
/// - Business logic errors (P0001 from RAISE EXCEPTION) are mapped to
///   [IntegrityException] with the original message intact.
///
/// **Usage:**
/// ```dart
/// class ContractRepository with PostgresErrorInterceptor {
///   Future<void> save(Contract contract) async {
///     try {
///       await _client.from('contracts').insert(contract.toJson());
///     } on PostgrestException catch (e) {
///       throw mapPostgrestToDomainException(
///         e,
///         resourceType: 'contract',
///         resourceId: contract.id,
///       );
///     }
///   }
/// }
/// ```
///
/// **Error Code Mapping:**
/// | PostgREST Code | Meaning                    | Domain Exception                |
/// |----------------|----------------------------|---------------------------------|
/// | 22P02          | invalid_text_representation| ResourceNotFoundException        |
/// | 23503          | foreign_key_violation      | ResourceNotFoundException        |
/// | PGRST116       | not_found                  | ResourceNotFoundException        |
/// | PGRST204       | column_not_found           | ResourceNotFoundException        |
/// | P0001          | RAISE EXCEPTION            | IntegrityException(message)      |
/// | 23505          | unique_violation           | IntegrityException               |
/// | 23502          | not_null_violation         | IntegrityException               |
/// | 42501          | insufficient_privilege     | SovereigntyViolationException    |
mixin PostgresErrorInterceptor {
  /// Maps a [PostgrestException] to the appropriate domain-layer exception.
  ///
  /// [resourceType] and [resourceId] are optional forensic metadata captured
  /// for internal security logging (Sentry/PostHog). They are NEVER exposed
  /// to the external HTTP response.
  Exception mapPostgrestToDomainException(
    PostgrestException e, {
    String? resourceType,
    String? resourceId,
  }) {
    final nested = _parseNestedError(e.message);
    final code = nested['code'] ?? e.code;
    final message = nested['message'] ?? e.message;
    final details = nested['details'] ?? (e.details as String?);

    return switch (code) {
      // Information Disclosure: Malformed UUIDs, missing columns, not-found rows,
      // FK violations (referenced resource doesn't exist or belongs to another org)
      // All map to ResourceNotFoundException → canonical 404 (INV-26)
      '22P02' || // invalid_text_representation
      '23503' || // foreign_key_violation
      'PGRST116' || // not_found
      'PGRST204' => // column_not_found
      ResourceNotFoundException(
        resourceType: resourceType,
        resourceId: resourceId,
      ),

      // Business Logic: RAISE EXCEPTION from Postgres functions/triggers
      // Message is passed through for domain-level handling
      'P0001' => IntegrityException(message),

      // Tenant Isolation: RLS denied access — map to SovereigntyViolation
      // so callers never inspect raw DB codes (INV-2 / INV-26 Oracle Attack prevention).
      '42501' => SovereigntyViolationException(
        payloadOrgId: resourceId ?? '',
        jwtOrgId: '',
        message: 'RLS policy denied access (42501 insufficient_privilege)',
      ),

      // Integrity: Unique constraint violations
      // Mapped to IntegrityException for caller-level handling
      '23505' => IntegrityException(
        message,
        field: _extractFieldFromUniqueViolation(details),
      ),

      // Not-null violation: a required field arrived null (e.g. an unmapped CSV
      // column). Surface a clear domain error instead of leaking the raw DB
      // code or letting it masquerade as a transport/connection failure.
      '23502' => const IntegrityException(
        'Campo obrigatório não preenchido em uma ou mais linhas. '
        'Verifique o mapeamento das colunas obrigatórias.',
      ),

      // Fail-Fast: Unhandled codes are rethrown — no silent failures (INV-10)
      _ => throw e,
    };
  }

  /// Decodes nested error payload inside [message] if it is JSON-formatted.
  Map<String, String?> _parseNestedError(String message) {
    final trimmed = message.trim();
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final decoded = json.decode(trimmed) as Map<String, dynamic>;
        return {
          'code': decoded['code']?.toString(),
          'message': decoded['message']?.toString(),
          'details': decoded['details']?.toString(),
        };
      } catch (_) {
        // Not a JSON or failed to decode
      }
    }
    return const {};
  }

  /// Extracts the field name from a unique violation details string.
  ///
  /// Example: "Key (cnpj)=(12.345.678/0001-90) already exists." → "cnpj"
  String? _extractFieldFromUniqueViolation(String? details) {
    if (details == null) return null;
    final match = RegExp(r'Key \((\w+)\)=').firstMatch(details);
    return match?.group(1);
  }
}
