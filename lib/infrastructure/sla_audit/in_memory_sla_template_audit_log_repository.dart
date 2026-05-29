import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/sla_audit/i_sla_template_audit_log_repository.dart';
import 'package:veraprob/domain/sla_audit/sla_template_audit_entry.dart';

/// In-memory append-only [ISlaTemplateAuditLogRepository] for test mode.
class InMemorySlaTemplateAuditLogRepository
    implements ISlaTemplateAuditLogRepository {
  final List<SlaTemplateAuditEntry> _entries = [];

  /// Returns a copy of the recorded entries for testing/verification.
  List<SlaTemplateAuditEntry> get entries => List.unmodifiable(_entries);

  @override
  Future<void> append(SlaTemplateAuditEntry entry) async {
    if (_entries.any((e) => e.id == entry.id)) {
      throw IntegrityException(
        'SlaTemplateAuditEntry with ID "${entry.id}" already exists',
        field: 'id',
      );
    }
    _entries.add(entry);
  }
}
