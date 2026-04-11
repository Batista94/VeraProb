/// Domain-layer exception for tenant isolation violations (INV-1).
///
/// Thrown when the `organization_id` in the request payload does NOT match
/// the `organization_id` claim in the authenticated user's JWT.
///
/// **Forensic Fields:** [payloadOrgId] and [jwtOrgId] are captured for
/// internal security logging (Sentry/PostHog) ONLY.
///
/// **External Response:** The [SovereigntyErrorMapper] strips all forensic
/// details and returns an indistinguishable `{"error": "Not Found"}` 404
/// to prevent Oracle Attacks (INV-26).
///
/// **Defense-in-Depth:** [toString] returns a sanitized message WITHOUT
/// forensic org IDs. Use [toForensicString] ONLY from internal security
/// loggers (e.g., [ForensicSecurityLogger]). This prevents accidental
/// leakage of tenant IDs if a generic UI logger calls toString().
class SovereigntyViolationException implements Exception {
  /// Forensic: the org_id claimed by the request payload.
  final String payloadOrgId;

  /// Forensic: the org_id extracted from the authenticated user's JWT.
  final String jwtOrgId;

  /// Internal audit message — never exposed to the client.
  final String message;

  const SovereigntyViolationException({
    required this.payloadOrgId,
    required this.jwtOrgId,
    this.message = 'Tenant isolation violation.',
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SovereigntyViolationException &&
        other.payloadOrgId == payloadOrgId &&
        other.jwtOrgId == jwtOrgId &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(payloadOrgId, jwtOrgId, message);

  /// Sanitized string — safe for generic loggers and UI error displays.
  ///
  /// Does NOT include forensic org IDs. If a generic logger or error boundary
  /// calls this, no tenant enumeration data is leaked. // pr_scanner: ignore
  @override
  String toString() => 'SovereigntyViolationException: $message';

  /// Forensic detail — ONLY call from internal security loggers.
  ///
  /// Use [ForensicSecurityLogger.logIdentitySpoofing] which handles
  /// Sentry tagging automatically. DO NOT pass this to UI or HTTP responses.
  String toForensicString() =>
      'SovereigntyViolationException: $message '
      '(payloadOrgId: $payloadOrgId, jwtOrgId: $jwtOrgId)';
}
