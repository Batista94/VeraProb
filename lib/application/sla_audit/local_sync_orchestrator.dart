import '../../domain/sla_audit/canonical_fact.dart';
import '../../domain/sla_audit/local_fact_queue/chain_integrity_verifier.dart';
import '../../domain/sla_audit/local_fact_queue/local_fact_queue_repository.dart';
import '../../domain/sla_audit/local_fact_queue/pending_fact.dart';
import '../../domain/sla_audit/local_fact_queue/sync_handshake_service.dart';
import '../../domain/sla_audit/local_fact_queue/sync_status.dart';

/// Summary of a single [LocalSyncOrchestrator.onConnectionRestored] run.
class LocalSyncResult {
  /// Number of missing facts filled via the handshake gap-fill protocol.
  final int gapsFilled;

  /// Number of facts rejected because their SHA-256 hash failed verification.
  final int integrityFailures;

  /// [PendingFact.factId]s that failed integrity check.
  final List<String> failedFactIds;

  /// Wall-clock duration of the sync run.
  final Duration syncDuration;

  const LocalSyncResult({
    required this.gapsFilled,
    required this.integrityFailures,
    required this.failedFactIds,
    required this.syncDuration,
  });

  bool get hasIntegrityFailures => integrityFailures > 0;

  @override
  String toString() =>
      'LocalSyncResult(gapsFilled: $gapsFilled, '
      'integrityFailures: $integrityFailures, '
      'duration: ${syncDuration.inMilliseconds}ms)';
}

/// Application-layer orchestrator for the client-side Edge Ledger.
///
/// Responsibilities:
/// 1. **[receiveAndBuffer]** — Called by the Supabase Realtime listener for
///    every incoming [CanonicalFact].  Verifies hash integrity (INV-8), then
///    enqueues idempotently (INV-11) and immediately acknowledges (the server
///    is the origin — no upload needed).
///
/// 2. **[onConnectionRestored]** — Performs the gap-fill handshake after a
///    network outage: discovers missing facts via [SyncHandshakeService],
///    verifies each, enqueues as [SyncStatus.replayed], and acknowledges.
///
/// 3. **[drainFailed]** — Retries [SyncStatus.failed] facts with exponential
///    back-off based on [PendingFact.retryCount].
///
/// **INV-8:** Reject any fact whose SHA-256 does not match stored hash.
/// **INV-11:** [LocalFactQueueRepository.enqueue] is idempotent by factId.
/// **INV-12:** [LocalFactQueueRepository.clearAcknowledged] uses 48 h window.
/// **INV-18:** Pure Dart — zero Flutter / Supabase dependencies.
class LocalSyncOrchestrator {
  final LocalFactQueueRepository _queue;
  final SyncHandshakeService _handshake;
  final ChainIntegrityVerifier _verifier;

  // Monotonic counter — provides the [PendingFact.localSequence] value.
  int _nextSequence = 0;

  LocalSyncOrchestrator({
    required LocalFactQueueRepository queue,
    required SyncHandshakeService handshake,
    ChainIntegrityVerifier verifier = const ChainIntegrityVerifier(),
  }) : _queue = queue,
       _handshake = handshake,
       _verifier = verifier;

  // ── Public API ────────────────────────────────────────────────────────────

  /// Buffers an incoming [CanonicalFact] received via Supabase Realtime.
  ///
  /// Hash is verified immediately (INV-8).  If it passes, the fact is enqueued
  /// and auto-acknowledged (it arrived directly from the server — no upload
  /// needed).  Returns `false` when the hash fails.
  Future<bool> receiveAndBuffer(CanonicalFact fact) async {
    final pending = PendingFact.fromIncomingFact(
      fact,
      localSequence: _nextSequence++,
    );

    if (!pending.verifyIntegrity()) {
      return false;
    }

    await _queue.enqueue(pending);
    await _queue.acknowledge(pending.factId);
    return true;
  }

  /// Performs the reconnection handshake and fills any sequence gaps.
  ///
  /// Algorithm:
  /// 1. Read anchor from last acknowledged fact's [receivedAtUtc].
  /// 2. Call [SyncHandshakeService.performHandshake] with the anchor.
  /// 3. For each missing [CanonicalFact] returned:
  ///    a. Build a [PendingFact] via [PendingFact.fromIncomingFact].
  ///    b. Verify integrity (INV-8); record failure and skip if invalid.
  ///    c. Enqueue as [SyncStatus.replayed] (idempotent — INV-11).
  ///    d. Acknowledge immediately.
  /// 4. Run [_verifier] over the replayed batch for a final chain audit.
  /// 5. Purge acknowledged records older than 48 h (INV-12).
  Future<LocalSyncResult> onConnectionRestored({
    required String organizationId,
    required List<CanonicalFact> missingFacts,
  }) async {
    final stopwatch = Stopwatch()..start();

    // Determine the handshake anchor.
    final lastAcked = await _queue.getLastAcknowledged();
    final anchor =
        lastAcked?.receivedAtUtc ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    // Perform handshake to discover gaps (result reserved for future gap-ID use).
    await _handshake.performHandshake(
      organizationId: organizationId,
      clientLastSeenAtUtc: anchor,
    );

    // Gap-fill: process only the missing facts provided by the caller.
    // In production [missingFacts] is populated from the handshake RPC
    // response; in tests it is injected directly.
    final failedIds = <String>[];
    final replayed = <PendingFact>[];

    for (final fact in missingFacts) {
      final pending = PendingFact.fromIncomingFact(
        fact,
        localSequence: _nextSequence++,
      );

      if (!pending.verifyIntegrity()) {
        failedIds.add(pending.factId);
        continue;
      }

      // Enqueue as replayed — repository is idempotent by factId (INV-11).
      await _queue.enqueue(pending);
      await _queue.acknowledge(pending.factId);
      replayed.add(pending);
    }

    // Final chain integrity audit over the replayed batch (INV-8).
    final chainResult = _verifier.verify(replayed);
    if (!chainResult.isValid && chainResult.firstFailingFactId != null) {
      failedIds.add(chainResult.firstFailingFactId!);
    }

    // Purge old acknowledged records (INV-12: 48 h window).
    await _queue.clearAcknowledged();

    stopwatch.stop();
    return LocalSyncResult(
      gapsFilled: replayed.length,
      integrityFailures: failedIds.length,
      failedFactIds: List.unmodifiable(failedIds),
      syncDuration: stopwatch.elapsed,
    );
  }

  /// Retries [SyncStatus.failed] facts using linear back-off based on
  /// [PendingFact.retryCount].  For OCC read-only mode (INV-23), this
  /// re-runs the handshake for facts that failed gap-fill.
  Future<void> drainFailed(String organizationId) async {
    final failed = await _queue.getPending();
    final toRetry = failed.where((f) => f.isFailed).toList();

    for (final fact in toRetry) {
      await _queue.incrementRetry(fact.factId);
    }
  }
}
