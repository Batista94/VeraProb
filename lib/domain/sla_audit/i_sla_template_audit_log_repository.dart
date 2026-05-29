import 'package:veraprob/domain/sla_audit/sla_template_audit_entry.dart';

/// Append-only port for the SLA template change history (INV-3).
///
/// Intentionally exposes no update/delete: entries are immutable facts.
abstract interface class ISlaTemplateAuditLogRepository {
  Future<void> append(SlaTemplateAuditEntry entry);
}
