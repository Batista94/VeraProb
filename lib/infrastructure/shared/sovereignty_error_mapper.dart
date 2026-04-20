import 'dart:convert';

import 'package:veraprob/domain/shared/resource_not_found_exception.dart';
import 'package:veraprob/domain/shared/sovereignty_violation_exception.dart';

/// Static utility that maps domain exceptions to indistinguishable
/// HTTP 404 responses (INV-26: Error Parity).
///
/// **Security Contract:**
/// - Both [SovereigntyViolationException] and [ResourceNotFoundException]
///   produce byte-identical responses: `{"error":"Not Found"}` with status 404.
/// - NO forensic details (org IDs, resource types, internal messages) are
///   leaked to the external caller.
/// - Internal forensic data MUST be logged separately (Sentry/PostHog).
///
/// **Usage in Edge Functions:**
/// ```dart
/// try {
///   await tenantValidationService.assertTenantMatches(...);
/// } on SovereigntyViolationException catch (e) {
///   // Log to Sentry internally
///   Sentry.captureException(e);
///   // Return indistinguishable 404
///   final response = SovereigntyErrorMapper.toResponse(e);
///   return Response.json(jsonDecode(response['body'] as String),
///     status: response['status'] as int);
/// }
/// ```
class SovereigntyErrorMapper {
  SovereigntyErrorMapper._();

  /// The canonical HTTP status code for all sovereignty/not-found errors.
  static const int statusCode = 404;

  /// The canonical response body — identical for all mapped exceptions.
  static const String _canonicalBody = '{"error":"Not Found"}';

  /// Maps a domain exception to an HTTP 404 response.
  ///
  /// **INV-26:** The response is indistinguishable regardless of whether
  /// the exception is a [SovereigntyViolationException] (tenant spoofing)
  /// or a [ResourceNotFoundException] (real 404 / cross-org access).
  ///
  /// The exception parameter is accepted for type safety and future
  /// extension (e.g., structured logging hooks), but the output is
  /// always the canonical `{"error":"Not Found"}`.
  static Map<String, dynamic> toResponse(Exception _) {
    return {'status': statusCode, 'body': _canonicalBody};
  }

  /// Returns the raw JSON body string for direct use in Response.json().
  static String get canonicalBody => _canonicalBody;

  /// Decodes the canonical body to a Map for Response.json() usage.
  static Map<String, dynamic> get decodedBody =>
      jsonDecode(_canonicalBody) as Map<String, dynamic>;
}
