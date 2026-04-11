import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/resource_not_found_exception.dart';

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
/// | PostgREST Code | Meaning                    | Domain Exception            |
/// |----------------|----------------------------|-----------------------------|
/// | 22P02          | invalid_text_representation| ResourceNotFoundException   |
/// | 23503          | foreign_key_violation      | ResourceNotFoundException   |
/// | PGRST116       | not_found                  | ResourceNotFoundException   |
/// | PGRST204       | column_not_found           | ResourceNotFoundException   |
/// | P0001          | RAISE EXCEPTION            | IntegrityException(message) |
/// | 23505          | unique_violation           | IntegrityException          |
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
    return switch (e.code) {
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
      'P0001' => IntegrityException(e.message),

      // Integrity: Unique constraint violations
      // Mapped to IntegrityException for caller-level handling
      '23505' => IntegrityException(
        e.message,
        field: _extractFieldFromUniqueViolation(
          e.details is String ? e.details as String : null,
        ),
      ),

      // Fail-Fast: Unhandled codes are rethrown — no silent failures (INV-10)
      _ => throw e,
    };
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
