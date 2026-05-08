// pr_scanner: ignore-regression
//
/// Read-only projection of a `system_audit_log` row for the SuperAdmin UI.
///
/// INV-4: Pure Dart — no infrastructure dependencies.
class SystemAuditLogEntry {
  final String severity;
  final String eventType;
  final String occurredAt;
  final String? organizationId;
  final Map<String, dynamic>? payload;

  /// Origin of the event: 'system', 'flutter_web', 'edge_function', etc.
  final String? source;

  /// Stage C: Actor type — HUMAN, IMPERSONATOR, SYSTEM.
  final String? actorType;

  /// Stage C: Governance justification reason.
  final String? reason;

  /// Stage C: Impersonator SuperAdmin ID when actor_type is IMPERSONATOR.
  final String? impersonatorId;

  const SystemAuditLogEntry({
    required this.severity,
    required this.eventType,
    required this.occurredAt,
    this.organizationId,
    this.payload,
    this.source,
    this.actorType,
    this.reason,
    this.impersonatorId,
  });

  factory SystemAuditLogEntry.fromJson(Map<String, dynamic> json) {
    return SystemAuditLogEntry(
      severity: json['severity'] as String? ?? 'info',
      eventType: json['event_type'] as String? ?? '',
      occurredAt: json['occurred_at'] as String? ?? '',
      organizationId: json['organization_id'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
      source: json['source'] as String?,
      actorType: json['actor_type'] as String?,
      reason: json['reason'] as String?,
      impersonatorId: json['impersonator_id'] as String?,
    );
  }
}
