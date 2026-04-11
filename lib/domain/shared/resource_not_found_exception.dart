/// Domain-layer exception for unified resource not found (INV-26, INV-27).
///
/// Thrown when:
/// 1. A resource truly does not exist (real 404), OR
/// 2. A resource exists but belongs to another organization (INV-27: Origin
///    Ownership — treat as "not found" to prevent data inference).
///
/// **Forensic Fields:** [resourceType] and [resourceId] are captured for
/// internal security logging (Sentry/PostHog) ONLY.
///
/// **External Response:** The [SovereigntyErrorMapper] strips all forensic
/// details and returns an indistinguishable `{"error": "Not Found"}` 404
/// to prevent Oracle Attacks (INV-26).
///
/// **Defense-in-Depth:** [toString] returns a sanitized message WITHOUT
/// forensic resource details. Use [toForensicString] ONLY from internal
/// security loggers. This prevents accidental leakage of resource
/// existence/type if a generic UI logger calls toString().
class ResourceNotFoundException implements Exception {
  /// Internal forensic type (e.g., 'contract', 'asset', 'sla_template').
  final String? resourceType;

  /// Internal forensic resource identifier.
  final String? resourceId;

  /// Internal audit message — never exposed to the client.
  final String message;

  const ResourceNotFoundException({
    this.resourceType,
    this.resourceId,
    this.message = 'Resource not found.',
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResourceNotFoundException &&
        other.resourceType == resourceType &&
        other.resourceId == resourceId &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(resourceType, resourceId, message);

  /// Sanitized string — safe for generic loggers and UI error displays.
  ///
  /// Does NOT include forensic resource details. If a generic logger or
  /// error boundary calls this, no resource enumeration data is leaked.
  @override
  String toString() => 'ResourceNotFoundException: $message';

  /// Forensic detail — ONLY call from internal security loggers.
  ///
  /// DO NOT pass to UI or HTTP responses.
  String toForensicString() {
    final buffer = StringBuffer('ResourceNotFoundException: $message');
    if (resourceType != null || resourceId != null) {
      buffer.write(' (');
      if (resourceType != null) buffer.write('resourceType: $resourceType');
      if (resourceId != null) {
        if (resourceType != null) buffer.write(', ');
        buffer.write('resourceId: $resourceId');
      }
      buffer.write(')');
    }
    return buffer.toString();
  }
}
