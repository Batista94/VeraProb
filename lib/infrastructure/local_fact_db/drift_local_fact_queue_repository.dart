import 'package:drift/drift.dart';

import 'package:veraprob/domain/sla_audit/local_fact_queue/local_fact_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/pending_fact.dart'
    as domain;
import 'package:veraprob/domain/sla_audit/local_fact_queue/sync_status.dart';
import 'package:veraprob/infrastructure/local_fact_db/local_fact_database.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// Drift-backed implementation of [LocalFactQueueRepository].
///
/// Uses `edge_ledger_v1.db` (WasmDatabase on Flutter Web, native SQLite
/// on other platforms).
///
/// **INV-11:** `insertOnConflictUpdate` â€” idempotent by (factId, contentHash UNIQUE).
/// **INV-12:** `clearAcknowledged` deletes records older than 48 h.
class DriftLocalFactQueueRepository implements LocalFactQueueRepository {
  final LocalFactDatabase _db;
  final IDateTimeProvider _dateTimeProvider;

  DriftLocalFactQueueRepository(this._db, this._dateTimeProvider);

  @override
  Future<void> enqueue(domain.PendingFact fact) async {
    await _db.into(_db.pendingFacts).insertOnConflictUpdate(fact.toCompanion());
  }

  @override
  Future<List<domain.PendingFact>> getPending({int limit = 50}) async {
    final rows =
        await (_db.select(_db.pendingFacts)
              ..orderBy([(t) => OrderingTerm.asc(t.localSequence)])
              ..limit(limit))
            .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<domain.PendingFact?> getLastAcknowledged() async {
    final row =
        await (_db.select(_db.pendingFacts)
              ..where((t) => t.syncStatus.equals(SyncStatus.acknowledged.name))
              ..orderBy([(t) => OrderingTerm.desc(t.localSequence)])
              ..limit(1))
            .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> acknowledge(String factId) async {
    await (_db.update(
      _db.pendingFacts,
    )..where((t) => t.factId.equals(factId))).write(
      PendingFactsCompanion(syncStatus: Value(SyncStatus.acknowledged.name)),
    );
  }

  @override
  Future<void> markFailed(String factId, String error) async {
    await (_db.update(
      _db.pendingFacts,
    )..where((t) => t.factId.equals(factId))).write(
      PendingFactsCompanion(
        syncStatus: Value(SyncStatus.failed.name),
        errorMessage: Value(error),
      ),
    );
  }

  @override
  Future<void> incrementRetry(String factId) async {
    final current = await _currentRetryCount(factId);
    await (_db.update(_db.pendingFacts)..where((t) => t.factId.equals(factId)))
        .write(PendingFactsCompanion(retryCount: Value(current + 1)));
  }

  @override
  Stream<int> watchPendingCount() {
    return (_db.selectOnly(_db.pendingFacts)
          ..addColumns([_db.pendingFacts.factId.count()]))
        .watchSingle()
        .map((row) => row.read(_db.pendingFacts.factId.count()) ?? 0);
  }

  @override
  Future<void> clearAcknowledged({
    Duration olderThan = const Duration(hours: 48),
  }) async {
    final cutoff = _dateTimeProvider.nowUtc().subtract(olderThan);
    await (_db.delete(_db.pendingFacts)..where(
          (t) =>
              t.syncStatus.equals(SyncStatus.acknowledged.name) &
              t.queuedAtUtc.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  // â”€â”€ Helpers â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

  Future<int> _currentRetryCount(String factId) async {
    final row =
        await (_db.select(_db.pendingFacts)
              ..where((t) => t.factId.equals(factId))
              ..limit(1))
            .getSingleOrNull();
    return row?.retryCount ?? 0;
  }
}
