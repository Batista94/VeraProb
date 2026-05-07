import 'package:veraprob/features/super_admin/domain/cnpj_exceptions.dart';

/// HTTP 4xx (excluding 429) or 5xx from the upstream registry or proxy.
///
/// Raw status codes and response bodies are intentionally excluded (INV-28).
/// [sanitizedCode] is one of: 'upstream_client_error' | 'upstream_server_error'.
class ExternalApiException extends CnpjLookupException {
  final String sanitizedCode;

  const ExternalApiException(
    super.message, {
    required this.sanitizedCode,
    super.cnpj,
  });

  factory ExternalApiException.fromStatusCode(int statusCode, {String? cnpj}) {
    final code = statusCode >= 500
        ? 'upstream_server_error'
        : 'upstream_client_error';
    return ExternalApiException(
      'Upstream request failed',
      sanitizedCode: code,
      cnpj: cnpj,
    );
  }

  @override
  String toString() => 'ExternalApiException: $message (code: $sanitizedCode)';
}

/// Connection timed out before the registry responded.
class ServiceTimeoutException extends CnpjLookupException {
  const ServiceTimeoutException(super.message, {super.cnpj});

  @override
  String toString() => 'ServiceTimeoutException: $message';
}

/// HTTP 429 — upstream registry is rate-limiting requests.
///
/// [retryAfter] is deliberately absent (timing oracle + cross-tenant
/// bucket inference risk — QA-Security ruling).
class RateLimitExceededException extends CnpjLookupException {
  const RateLimitExceededException(super.message, {super.cnpj});

  @override
  String toString() => 'RateLimitExceededException: $message';
}
