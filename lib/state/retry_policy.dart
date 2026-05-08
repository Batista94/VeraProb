import 'dart:math';

import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, FunctionException;

/// HTTP exception with a numeric status code.
///
/// Used by the retry policy to classify errors as recoverable or
/// non-recoverable based on HTTP semantics. This covers generic HTTP
/// errors that don't originate from Supabase-specific clients.
class HttpException implements Exception {
  const HttpException(this.statusCode, [this.message = '']);

  /// The HTTP status code (e.g. 400, 500).
  final int statusCode;

  /// Optional human-readable message.
  final String message;

  @override
  String toString() => 'HttpException: $statusCode $message';
}

/// Non-recoverable HTTP status codes that should never be retried.
///
/// - 400: Bad Request (malformed input)
/// - 401: Unauthorized (invalid/expired credentials)
/// - 403: Forbidden (insufficient permissions)
/// - 404: Not Found (resource doesn't exist)
/// - 409: Conflict (state conflict, e.g. duplicate)
/// - 422: Unprocessable Entity (validation failure)
const _nonRecoverableStatusCodes = {400, 401, 403, 404, 409, 422};

/// Extracts an HTTP status code from known exception types.
///
/// Returns `null` if the error doesn't carry an HTTP status code.
int? _extractStatusCode(Object error) {
  if (error is HttpException) return error.statusCode;
  if (error is FunctionException) return error.status;
  if (error is AuthException) {
    return int.tryParse(error.statusCode ?? '');
  }
  return null;
}

/// Classifies whether an error is recoverable for retry purposes.
///
/// Returns `null` to disable retry, or a [Duration] to schedule the next
/// retry attempt with exponential backoff and jitter.
///
/// **Validates: Requirements 7.1, 7.2, 7.3, 7.4, 7.5**
///
/// Rules:
/// - [ProviderException] (dependency failure) → no retry
/// - HTTP 400, 401, 403, 404, 409, 422 → no retry (non-recoverable)
/// - retryCount > 5 → no retry (max attempts reached)
/// - Otherwise → exponential backoff: min(200ms × 2^retryCount, 6400ms) ± 10% jitter
Duration? classifyForRetry(int retryCount, Object error) {
  // Falha por dependência — não retry
  if (error is ProviderException) return null;

  // Limite de tentativas
  if (retryCount > 5) return null;

  // Erros HTTP não-recuperáveis (suporta HttpException, FunctionException, AuthException)
  final statusCode = _extractStatusCode(error);
  if (statusCode != null && _nonRecoverableStatusCodes.contains(statusCode)) {
    return null;
  }

  // Backoff exponencial com jitter
  final base = min(200 * pow(2, retryCount), 6400).toInt();
  final jitter = (Random().nextDouble() * 0.2 - 0.1) * base;
  return Duration(milliseconds: base + jitter.round());
}
