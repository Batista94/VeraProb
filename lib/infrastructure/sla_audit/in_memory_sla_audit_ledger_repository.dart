import '../../domain/sla_audit/sla_audit_ledger_repository.dart';
import '../../domain/sla_audit/sla_ledger_entry.dart';

/// In-memory implementation of [SlaAuditLedgerRepository].
///
/// Simply stores forensic entries in a list. Append-only by design.
class InMemorySlaAuditLedgerRepository implements SlaAuditLedgerRepository {
  final List<SlaLedgerEntry> _entries = [];
  int _nextId = 1;

  @override
  Future<void> append(SlaLedgerEntry entry) async {
    final entryWithId = SlaLedgerEntry(
      id: _nextId++,
      type: entry.type,
      setId: entry.setId,
      contractId: entry.contractId,
      planVersion: entry.planVersion,
      occurredAtUtc: entry.occurredAtUtc,
      payload: entry.payload,
    );
    _entries.add(entryWithId);
  }

  @override
  Future<int?> getLastEntryId() async {
    if (_entries.isEmpty) return null;
    return _entries.last.id;
  }

  /// Returns a copy of the recorded entries for testing/verification.
  List<SlaLedgerEntry> get entries => List.unmodifiable(_entries);
}
