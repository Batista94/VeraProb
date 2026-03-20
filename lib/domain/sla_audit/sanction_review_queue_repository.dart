import 'sanction_review_queue_entry.dart';

/// Port (abstract repository) for the Sanction Review Queue.
///
/// **Constraints:**
/// - [enqueue] is called by the application layer when a SANCTION_RECOMMENDED
///   event is processed (though in production this is handled by a DB trigger).
/// - [updateStatus] is the ONLY mutation allowed — changes status field only.
///   Immutable fields (org_id, ledger_entry_id, etc.) are protected by DB trigger.
/// - No delete operation exists (INV-1).
abstract class SanctionReviewQueueRepository {
  Future<void> enqueue(SanctionReviewQueueEntry entry);

  Future<SanctionReviewQueueEntry?> findById(
    String id, {
    required String organizationId,
  });

  Future<List<SanctionReviewQueueEntry>> findPending({
    required String organizationId,
  });

  Future<void> updateStatus(SanctionReviewQueueEntry entry);
}
