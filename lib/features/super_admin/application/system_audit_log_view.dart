import 'package:veraprob/features/super_admin/domain/system_audit_log_entry.dart';

/// Read model for a system audit log entry used in the presentation layer.
///
/// [payload] uses `Map<String, Object?>` — never `dynamic` (INV-18).
class SystemAuditLogView {
  final String severity;
  final String eventType;
  final String occurredAt;
  final String? organizationId;
  final Map<String, Object?>? payload;

  /// Origin of the event: 'system', 'flutter_web', 'edge_function', etc.
  final String? source;

  /// Stage C: Actor type — HUMAN, IMPERSONATOR, SYSTEM.
  final String? actorType;

  /// Stage C: Governance justification reason.
  final String? reason;

  /// Stage C: Impersonator SuperAdmin ID when actor_type is IMPERSONATOR.
  final String? impersonatorId;

  const SystemAuditLogView({
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

  factory SystemAuditLogView.fromDomain(SystemAuditLogEntry domain) {
    return SystemAuditLogView(
      severity: domain.severity,
      eventType: domain.eventType,
      occurredAt: domain.occurredAt,
      organizationId: domain.organizationId,
      payload: domain.payload?.cast<String, Object?>(),
      source: domain.source,
      actorType: domain.actorType,
      reason: domain.reason,
      impersonatorId: domain.impersonatorId,
    );
  }

  factory SystemAuditLogView.fromJson(Map<String, Object?> json) {
    final rawPayload = json['payload'];
    return SystemAuditLogView(
      severity: json['severity'] as String? ?? 'info',
      eventType: json['event_type'] as String? ?? '',
      occurredAt: json['occurred_at'] as String? ?? '',
      organizationId: json['organization_id'] as String?,
      payload: rawPayload is Map<String, Object?>
          ? rawPayload
          : rawPayload is Map
          ? Map<String, Object?>.from(rawPayload)
          : null,
      source: json['source'] as String?,
      actorType: json['actor_type'] as String?,
      reason: json['reason'] as String?,
      impersonatorId: json['impersonator_id'] as String?,
    );
  }
}
