import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/pending_fact.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/sync_status.dart';
import 'package:veraprob/infrastructure/local_fact_db/in_memory_local_fact_queue_repository.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

CanonicalFact makeCanonicalFact({int seq = 1}) => CanonicalFact.create(
  organizationId: 'org-test',
  rawPayloadId: 'raw-$seq',
  deviceId: 'DEV-$seq',
  sourceAdapter: 'SASCAR_V1',
  receivedAtUtc: DateTime.utc(2026, 5, 1, 10, seq, 0),
  gpsTimestamp: DateTime.utc(2026, 5, 1, 9, seq, 0),
  lat: -23.0,
  lng: -46.0,
  integrityFlag: IngestionIntegrityFlag.ok,
);

PendingFact makePending({int seq = 1}) => PendingFact.fromIncomingFact(
  makeCanonicalFact(seq: seq),
  localSequence: seq,
);

void main() {
  late InMemoryLocalFactQueueRepository repo;

  setUp(() {
    repo = InMemoryLocalFactQueueRepository(
      FakeDateTimeProvider(DateTime(2026, 4, 8, 10, 0, 0)),
    );
  });

  // ── enqueue ──────────────────────────────────────────────────────────────

  group('enqueue()', () {
    test('adds a fact to the store', () async {
      await repo.enqueue(makePending());
      final pending = await repo.getPending();
      expect(pending.length, 1);
    });

    test(
      'is idempotent — enqueue same factId twice stores only one record',
      () async {
        final fact = makePending();
        await repo.enqueue(fact);
        await repo.enqueue(fact);

        final pending = await repo.getPending(limit: 100);
        expect(pending.length, 1);
      },
    );

    test('preserves all fields of the enqueued fact', () async {
      final fact = makePending(seq: 7);
      await repo.enqueue(fact);

      final stored = (await repo.getPending()).first;
      expect(stored.factId, fact.factId);
      expect(stored.contentHash, fact.contentHash);
      expect(stored.localSequence, fact.localSequence);
    });
  });

  // ── getPending ───────────────────────────────────────────────────────────

  group('getPending()', () {
    test('returns empty list when store is empty', () async {
      expect(await repo.getPending(), isEmpty);
    });

    test('respects limit parameter', () async {
      for (var i = 1; i <= 10; i++) {
        await repo.enqueue(makePending(seq: i));
      }
      final result = await repo.getPending(limit: 3);
      expect(result.length, 3);
    });

    test('returns all facts when limit exceeds count', () async {
      for (var i = 1; i <= 5; i++) {
        await repo.enqueue(makePending(seq: i));
      }
      final result = await repo.getPending(limit: 100);
      expect(result.length, 5);
    });
  });

  // ── acknowledge ──────────────────────────────────────────────────────────

  group('acknowledge()', () {
    test('sets syncStatus to acknowledged', () async {
      final fact = makePending();
      await repo.enqueue(fact);
      await repo.acknowledge(fact.factId);

      final stored = (await repo.getPending(limit: 100)).first;
      expect(stored.syncStatus, SyncStatus.acknowledged);
    });

    test('no-op for unknown factId', () async {
      await expectLater(repo.acknowledge('unknown-id'), completes);
    });
  });

  // ── getLastAcknowledged ──────────────────────────────────────────────────

  group('getLastAcknowledged()', () {
    test('returns null when store is empty', () async {
      expect(await repo.getLastAcknowledged(), isNull);
    });

    test('returns null when no acknowledged fact exists', () async {
      await repo.enqueue(makePending());
      expect(await repo.getLastAcknowledged(), isNull);
    });

    test(
      'returns the acknowledged fact with the highest localSequence',
      () async {
        await repo.enqueue(makePending(seq: 1));
        await repo.enqueue(makePending(seq: 2));
        await repo.enqueue(makePending(seq: 3));

        final facts = await repo.getPending(limit: 100);
        await repo.acknowledge(facts[0].factId); // seq 1
        await repo.acknowledge(facts[2].factId); // seq 3

        final last = await repo.getLastAcknowledged();
        expect(last, isNotNull);
        expect(last!.localSequence, 3);
      },
    );
  });

  // ── markFailed ───────────────────────────────────────────────────────────

  group('markFailed()', () {
    test('sets syncStatus to failed with error message', () async {
      final fact = makePending();
      await repo.enqueue(fact);
      await repo.markFailed(fact.factId, 'network error');

      final stored = (await repo.getPending(limit: 100)).first;
      expect(stored.syncStatus, SyncStatus.failed);
      expect(stored.errorMessage, 'network error');
    });
  });

  // ── incrementRetry ───────────────────────────────────────────────────────

  group('incrementRetry()', () {
    test('increments retryCount by 1', () async {
      final fact = makePending();
      await repo.enqueue(fact);
      await repo.incrementRetry(fact.factId);

      final stored = (await repo.getPending(limit: 100)).first;
      expect(stored.retryCount, 1);
    });

    test('can increment multiple times', () async {
      final fact = makePending();
      await repo.enqueue(fact);
      await repo.incrementRetry(fact.factId);
      await repo.incrementRetry(fact.factId);
      await repo.incrementRetry(fact.factId);

      final stored = (await repo.getPending(limit: 100)).first;
      expect(stored.retryCount, 3);
    });
  });

  // ── clearAcknowledged ────────────────────────────────────────────────────

  group('clearAcknowledged()', () {
    test('removes acknowledged facts older than the window', () async {
      final oldFact = PendingFact.fromIncomingFact(
        makeCanonicalFact(seq: 1),
        localSequence: 1,
        nowUtc: DateTime.utc(2026, 1, 1), // very old
      );
      final recentFact = PendingFact.fromIncomingFact(
        makeCanonicalFact(seq: 2),
        localSequence: 2,
      );

      await repo.enqueue(oldFact);
      await repo.enqueue(recentFact);
      await repo.acknowledge(oldFact.factId);
      await repo.acknowledge(recentFact.factId);

      await repo.clearAcknowledged(olderThan: const Duration(hours: 48));

      final remaining = await repo.getPending(limit: 100);
      // old one removed; recent one kept (queuedAtUtc is now-ish)
      expect(remaining.any((f) => f.factId == oldFact.factId), isFalse);
    });

    test('does not remove pending facts', () async {
      final fact = PendingFact.fromIncomingFact(
        makeCanonicalFact(),
        localSequence: 1,
        nowUtc: DateTime.utc(2026, 1, 1),
      );
      await repo.enqueue(fact);
      // Not acknowledged — stays pending.

      await repo.clearAcknowledged(olderThan: const Duration(hours: 48));

      final remaining = await repo.getPending(limit: 100);
      expect(remaining.length, 1);
    });
  });

  // ── watchPendingCount ────────────────────────────────────────────────────

  group('watchPendingCount()', () {
    test('emits 0 initially', () async {
      await expectLater(repo.watchPendingCount().first, completion(0));
    });

    test('emits updated count after enqueue', () async {
      // Subscribe first so we don't miss emissions.
      final collected = <int>[];
      final sub = repo.watchPendingCount().listen(collected.add);

      await repo.enqueue(makePending(seq: 1));
      await Future<void>.delayed(Duration.zero);
      await repo.enqueue(makePending(seq: 2));
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();

      // Must have seen 0 (seed), then at least 2 at the end.
      expect(collected.first, 0);
      expect(collected.last, 2);
      expect(collected.length, greaterThanOrEqualTo(2));
    });

    test(
      'count decreases after clearAcknowledged removes old entries',
      () async {
        final oldFact = PendingFact.fromIncomingFact(
          makeCanonicalFact(seq: 1),
          localSequence: 1,
          nowUtc: DateTime.utc(2026, 1, 1),
        );
        await repo.enqueue(oldFact);
        await repo.acknowledge(oldFact.factId);

        final before = await repo.watchPendingCount().first;
        await repo.clearAcknowledged(olderThan: const Duration(hours: 48));
        final after = await repo.watchPendingCount().first;

        expect(before, 1);
        expect(after, 0);
      },
    );
  });
}
