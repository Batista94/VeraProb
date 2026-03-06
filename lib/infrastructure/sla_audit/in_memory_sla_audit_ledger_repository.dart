import 'package:uuid/uuid.dart';
import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import '../../domain/sla_audit/sla_ledger_entry.dart';

/// In-memory implementation of [SlaAuditLedgerRepository].
///
/// Simply stores forensic entries in a list. Append-only by design.
class InMemorySlaAuditLedgerRepository implements SlaAuditLedgerRepository {
  final List<SlaLedgerEntry> _entries = [];
  int _nextId = 1;

  @override
  Future<String> append(SlaLedgerEntry entry) async {
    final eventId = const Uuid().v4();
    final entryWithId = SlaLedgerEntry(
      id: _nextId++,
      eventId: eventId,
      organizationId: entry.organizationId,
      type: entry.type,
      setId: entry.setId,
      contractId: entry.contractId,
      planVersion: entry.planVersion,
      occurredAtUtc: entry.occurredAtUtc,
      payload: entry.payload,
    );
    _entries.add(entryWithId);
    return eventId;
  }

  @override
  Future<int?> getLastEntryId() async {
    if (_entries.isEmpty) return null;
    return _entries.last.id;
  }

  /// Returns a copy of the recorded entries for testing/verification.
  List<SlaLedgerEntry> get entries => List.unmodifiable(_entries);

  @override
  Future<List<SlaLedgerEntry>> getEntriesBySetId(String setId) async {
    return _entries.where((e) => e.setId == setId).toList()
      ..sort((a, b) => a.occurredAtUtc.compareTo(b.occurredAtUtc));
  }
}
