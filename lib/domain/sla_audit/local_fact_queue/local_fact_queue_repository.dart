import 'pending_fact.dart';
import 'sync_status.dart';

/// Domain boundary for local Edge Ledger persistence.
///
/// Implementations:
/// - [InMemoryLocalFactQueueRepository] — tests only.
/// - [DriftLocalFactQueueRepository]   — Flutter Web (WasmDatabase).
///
/// **INV-11:** [enqueue] is strictly idempotent by [PendingFact.factId].
/// **INV-18:** Interface is pure Dart — zero Flutter / Supabase dependencies.
abstract class LocalFactQueueRepository {
  /// Persists [fact] to the local queue.
  ///
  /// If a record with the same [PendingFact.factId] already exists the call
  /// is a no-op (ON CONFLICT DO NOTHING semantics).
  Future<void> enqueue(PendingFact fact);

  /// Returns up to [limit] facts whose [SyncStatus] is [SyncStatus.pending]
  /// or [SyncStatus.failed], ordered by [PendingFact.localSequence] ASC.
  Future<List<PendingFact>> getPending({int limit = 50});

  /// Returns the most recently [SyncStatus.acknowledged] fact, ordered by
  /// [PendingFact.localSequence] DESC.  Returns `null` when the queue is
  /// empty or no facts have been acknowledged yet.
  Future<PendingFact?> getLastAcknowledged();

  /// Marks a fact as [SyncStatus.acknowledged].
  /// No-op if [factId] does not exist.
  Future<void> acknowledge(String factId);

  /// Marks a fact as [SyncStatus.failed] and stores [error].
  /// No-op if [factId] does not exist.
  Future<void> markFailed(String factId, String error);

  /// Increments [PendingFact.retryCount] by 1.
  /// No-op if [factId] does not exist.
  Future<void> incrementRetry(String factId);

  /// Reactive count of facts with [SyncStatus.pending] or [SyncStatus.failed].
  /// Emits immediately and again on every queue mutation.
  Stream<int> watchPendingCount();

  /// Deletes all [SyncStatus.acknowledged] records older than [olderThan].
  ///
  /// Default window matches the late-arrival protocol (INV-12): 48 h.
  Future<void> clearAcknowledged({
    Duration olderThan = const Duration(hours: 48),
  });
}
