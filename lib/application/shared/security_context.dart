/// Application-layer Security Context DTO for forensic traceability.
///
/// **Purpose:** Carries traceability metadata from Edge Functions through
/// the full request lifecycle, enabling SOC to correlate a Sentry Alert
/// to a specific row in the raw_telemetry_payloads table in under 30 seconds.
///
/// **Layer:** Application DTO (NOT a Domain VO — carries no business invariants).
/// This class exists purely to structure observability data between the
/// infrastructure boundary (Edge Functions) and the forensic logger.
///
/// **SOC Parity Contract:**
/// - Every Sentry alert MUST include the full SecurityContext as tags + context.
/// - `correlationId` is the primary key for SOC investigation: it flows from
///   the Edge Function entry point → handler → forensic logger → Sentry → DB.
/// - `payloadHash` (SHA-256) enables direct lookup in `raw_telemetry_payloads`.
///
/// **Usage:**
/// ```dart
/// final ctx = SecurityContext(
///   correlationId: 'uuid-v4-from-edge-function',
///   edgeFunction: 'create_contract',
///   rawPayloadId: 'raw_payload_abc123',
///   requestIp: '192.168.1.1',
///   payloadHash: 'sha256-hex-digest',
/// );
///
/// ForensicSecurityLogger.logIdentitySpoofing(
///   payloadOrgId: cmd.organizationId,
///   jwtOrgId: user.tenantId,
///   sessionId: cmd.sessionId,
///   securityContext: ctx,
/// );
/// ```
class SecurityContext {
  /// UUID v4 — unique identifier for this request (forensic correlation).
  final String correlationId;

  /// Edge Function name (e.g., "create_contract", "ingest-sascar").
  final String edgeFunction;

  /// Storage key for the raw ingestion payload (if applicable).
  final String? rawPayloadId;

  /// ID of the normalized canonical fact (if applicable).
  final String? canonicalFactId;

  /// Client IP from X-Forwarded-For (or "unknown" if unavailable).
  final String requestIp;

  /// SHA-256 hex digest of the request body (INV-9: Evidence Sealing).
  final String? payloadHash;

  const SecurityContext({
    required this.correlationId,
    required this.edgeFunction,
    this.rawPayloadId,
    this.canonicalFactId,
    required this.requestIp,
    this.payloadHash,
  });

  /// Returns a map of Sentry tags for this context.
  ///
  /// Tags are flat key-value pairs used for filtering and searching
  /// Sentry alerts. All non-null fields are included.
  Map<String, String> toSentryTags() {
    final tags = <String, String>{
      'correlation_id': correlationId,
      'edge_function': edgeFunction,
      'request_ip': requestIp,
    };
    if (payloadHash != null) {
      tags['payload_hash'] = payloadHash!;
    }
    if (rawPayloadId != null) {
      tags['raw_payload_id'] = rawPayloadId!;
    }
    if (canonicalFactId != null) {
      tags['canonical_fact_id'] = canonicalFactId!;
    }
    return tags;
  }

  /// Returns a map of Sentry context data for this context.
  ///
  /// Context objects carry structured data beyond flat tags.
  /// Use this for the full forensic record in Sentry.
  Map<String, String?> toSentryContext() {
    return {
      'correlationId': correlationId,
      'edgeFunction': edgeFunction,
      'rawPayloadId': rawPayloadId,
      'canonicalFactId': canonicalFactId,
      'requestIp': requestIp,
      'payloadHash': payloadHash,
    };
  }
}
