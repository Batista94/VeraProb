import 'package:veraprob/domain/super_admin/system_audit_log_entry.dart';

/// Read model for a system audit log entry used in the presentation layer.
///
/// [payload] uses `Map<String, Object?>` — never `dynamic` (INV-18).
class SystemAuditLogView {
  final String severity;
  final String eventType;
  final String occurredAt;
  final String? organizationId;
  final Map<String, Object?>? payload;

  const SystemAuditLogView({
    required this.severity,
    required this.eventType,
    required this.occurredAt,
    this.organizationId,
    this.payload,
  });

  factory SystemAuditLogView.fromDomain(SystemAuditLogEntry domain) {
    return SystemAuditLogView(
      severity: domain.severity,
      eventType: domain.eventType,
      occurredAt: domain.occurredAt,
      organizationId: domain.organizationId,
      payload: domain.payload?.cast<String, Object?>(),
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
    );
  }
}
