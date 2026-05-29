import 'package:veraprob/domain/sla_audit/i_sla_template_audit_log_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_template_audit_entry.dart';

/// In-memory append-only [ISlaTemplateAuditLogRepository] for test mode.
class InMemorySlaTemplateAuditLogRepository
    implements ISlaTemplateAuditLogRepository {
  final List<SlaTemplateAuditEntry> entries = [];

  @override
  Future<void> append(SlaTemplateAuditEntry entry) async {
    entries.add(entry);
  }
}
