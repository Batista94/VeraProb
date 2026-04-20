import 'package:veraprob/domain/sla_audit/sanction_review_queue_entry.dart';
import 'package:veraprob/domain/sla_audit/sanction_review_queue_repository.dart';

/// In-memory implementation of [SanctionReviewQueueRepository].
///
/// Used in unit tests and in-memory persistence mode. Append semantics
/// for [enqueue]; [updateStatus] replaces the matching entry in the list.
class InMemorySanctionReviewQueueRepository
    implements SanctionReviewQueueRepository {
  final List<SanctionReviewQueueEntry> _entries = [];

  @override
  Future<void> enqueue(SanctionReviewQueueEntry entry) async {
    // INV-24: idempotent insert — ignore duplicates by ledger_entry_id
    final exists = _entries.any((e) => e.ledgerEntryId == entry.ledgerEntryId);
    if (!exists) {
      _entries.add(entry);
    }
  }

  @override
  Future<SanctionReviewQueueEntry?> findById(
    String id, {
    required String organizationId,
  }) async {
    try {
      return _entries.firstWhere(
        (e) => e.id == id && e.organizationId == organizationId,
      );
    } on StateError {
      return null;
    }
  }

  @override
  Future<List<SanctionReviewQueueEntry>> findPending({
    required String organizationId,
  }) async {
    return _entries
        .where(
          (e) =>
              e.organizationId == organizationId &&
              e.status == SanctionReviewStatus.pending,
        )
        .toList();
  }

  @override
  Future<void> updateStatus(SanctionReviewQueueEntry entry) async {
    final index = _entries.indexWhere((e) => e.id == entry.id);
    if (index != -1) {
      _entries[index] = entry;
    }
  }

  /// Returns a copy of all recorded entries for testing/verification.
  List<SanctionReviewQueueEntry> get entries => List.unmodifiable(_entries);
}
