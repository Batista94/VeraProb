import 'dart:async';

import '../../domain/sla_audit/local_fact_queue/local_fact_queue_repository.dart';
import '../../domain/sla_audit/local_fact_queue/pending_fact.dart';
import '../../domain/sla_audit/local_fact_queue/sync_status.dart';

/// In-memory implementation of [LocalFactQueueRepository].
///
/// Used exclusively in tests and as a fallback in non-WASM environments.
/// Enforces idempotency via factId uniqueness (INV-11).
///
/// **INV-18:** Pure Dart — zero Flutter / Supabase dependencies.
class InMemoryLocalFactQueueRepository implements LocalFactQueueRepository {
  final List<PendingFact> _facts = [];
  final StreamController<int> _countController =
      StreamController<int>.broadcast();

  // ── LocalFactQueueRepository ─────────────────────────────────────────────

  @override
  Future<void> enqueue(PendingFact fact) async {
    if (_facts.any((f) => f.factId == fact.factId)) return;
    _facts.add(fact);
    _emitCount();
  }

  @override
  Future<List<PendingFact>> getPending({int limit = 50}) async {
    return _facts.take(limit).toList();
  }

  @override
  Future<PendingFact?> getLastAcknowledged() async {
    final acked = _facts
        .where((f) => f.syncStatus == SyncStatus.acknowledged)
        .toList()
      ..sort((a, b) => a.localSequence.compareTo(b.localSequence));
    return acked.isEmpty ? null : acked.last;
  }

  @override
  Future<void> acknowledge(String factId) async {
    _update(factId, (f) => _copyWith(f, syncStatus: SyncStatus.acknowledged));
  }

  @override
  Future<void> markFailed(String factId, String error) async {
    _update(
      factId,
      (f) => _copyWith(f, syncStatus: SyncStatus.failed, errorMessage: error),
    );
  }

  @override
  Future<void> incrementRetry(String factId) async {
    _update(factId, (f) => _copyWith(f, retryCount: f.retryCount + 1));
  }

  @override
  Stream<int> watchPendingCount() {
    // Seed with current count synchronously before any enqueue events fire.
    return Stream<int>.multi((controller) {
      controller.add(_facts.length);
      final sub = _countController.stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  @override
  Future<void> clearAcknowledged({
    Duration olderThan = const Duration(hours: 48),
  }) async {
    final cutoff = DateTime.now().toUtc().subtract(olderThan);
    final before = _facts.length;
    _facts.removeWhere(
      (f) =>
          f.syncStatus == SyncStatus.acknowledged &&
          f.queuedAtUtc.isBefore(cutoff),
    );
    if (_facts.length != before) _emitCount();
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  void _update(String factId, PendingFact Function(PendingFact) transform) {
    final idx = _facts.indexWhere((f) => f.factId == factId);
    if (idx == -1) return;
    _facts[idx] = transform(_facts[idx]);
    _emitCount();
  }

  void _emitCount() => _countController.add(_facts.length);

  PendingFact _copyWith(
    PendingFact f, {
    SyncStatus? syncStatus,
    int? retryCount,
    String? errorMessage,
  }) =>
      PendingFact.reconstitute(
        factId: f.factId,
        organizationId: f.organizationId,
        contentHash: f.contentHash,
        factPayloadJson: f.factPayloadJson,
        receivedAtUtc: f.receivedAtUtc,
        queuedAtUtc: f.queuedAtUtc,
        syncStatus: syncStatus ?? f.syncStatus,
        localSequence: f.localSequence,
        retryCount: retryCount ?? f.retryCount,
        errorMessage: errorMessage ?? f.errorMessage,
      );
}
