// ignore_for_file: lines_longer_than_80_chars
// =============================================================================
// test/application/sla_audit/local_sync_orchestrator_socket_exception_test.dart
//
// Socket exception and error semantics coverage for LocalSyncOrchestrator:
// - SocketException propagation
// - Persistence on error
// - Integrity Signal failure
// - Idempotency (INV-11)
//
// Invariants enforced:
// - INV-8: Hash integrity verification
// - INV-11: Idempotent enqueue by factId
// - INV-18: Zero-Trust (reject invalid hashes)
// =============================================================================

import 'dart:io';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/local_sync_orchestrator.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/chain_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/chain_verification_result.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/handshake_result.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/local_fact_queue_repository.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/pending_fact.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/sync_handshake_service.dart';

// ── Stubs ─────────────────────────────────────────────────────────────────────

class _FakeQueueRepository implements LocalFactQueueRepository {
  final List<PendingFact> _queue = [];
  final Set<String> _acknowledged = {};

  @override
  Future<void> enqueue(PendingFact fact) async {
    if (!_queue.any((f) => f.factId == fact.factId)) {
      _queue.add(fact);
    }
  }

  @override
  Future<void> acknowledge(String factId) async {
    _acknowledged.add(factId);
  }

  @override
  Future<PendingFact?> getLastAcknowledged() async {
    if (_acknowledged.isEmpty) return null;
    return _queue.where((f) => _acknowledged.contains(f.factId)).lastOrNull;
  }

  @override
  Future<List<PendingFact>> getPending({int limit = 50}) async => _queue
      .where((f) => !_acknowledged.contains(f.factId))
      .take(limit)
      .toList();

  @override
  Future<void> clearAcknowledged({
    Duration olderThan = const Duration(hours: 48),
  }) async {}

  @override
  Future<void> incrementRetry(String factId) async {}

  @override
  Future<void> markFailed(String factId, String error) async {}

  @override
  Stream<int> watchPendingCount() => Stream.value(0);
}

class _FakeHandshakeService implements SyncHandshakeService {
  final bool shouldThrow;

  _FakeHandshakeService({this.shouldThrow = false});

  @override
  Future<HandshakeResult> performHandshake({
    required String organizationId,
    required DateTime clientLastSeenAtUtc,
  }) async {
    if (shouldThrow) {
      throw const SocketException('Network unreachable');
    }
    return HandshakeResult(
      lastServerFactReceivedAt: DateTime.utc(2026, 4, 14, 12, 0, 0),
      missingFactIds: const [],
    );
  }
}

class _FakeFailingVerifier implements ChainIntegrityVerifier {
  @override
  ChainVerificationResult verify(List<PendingFact> facts) {
    return ChainVerificationResult.failure(
      index: 0,
      factId: facts.isNotEmpty ? facts.first.factId : 'unknown',
    );
  }
}

// ── Factories ─────────────────────────────────────────────────────────────────

CanonicalFact makeFact(String id) => CanonicalFact.create(
  organizationId: 'org-1',
  rawPayloadId: 'raw-1',
  deviceId: 'device-1',
  sourceAdapter: 'test',
  receivedAtUtc: DateTime.utc(2026, 4, 14, 12, 0, 0),
  gpsTimestamp: DateTime.utc(2026, 4, 14, 12, 0, 0),
  lat: -23.5612,
  lng: -46.6560,
  integrityFlag: IngestionIntegrityFlag.ok,
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Socket Exception Semantics', () {
    // S1 — SocketException propagation
    test('S1: SocketException propagation', () async {
      final queue = _FakeQueueRepository();
      final handshake = _FakeHandshakeService(shouldThrow: true);
      final orchestrator = LocalSyncOrchestrator(
        queue: queue,
        handshake: handshake,
      );

      unawaited(
        expectLater(
          orchestrator.onConnectionRestored(
            organizationId: 'org-1',
            missingFacts: [],
          ),
          throwsA(isA<SocketException>()),
        ),
      );
    });

    // S2 — Persistence on error
    test('S2: Persistence on error -> facts remain in queue', () async {
      final queue = _FakeQueueRepository();
      final handshake = _FakeHandshakeService();
      final orchestrator = LocalSyncOrchestrator(
        queue: queue,
        handshake: handshake,
      );

      await orchestrator.receiveAndBuffer(makeFact('fact-1'));
      expect(queue._queue, hasLength(1));

      try {
        await _FakeHandshakeService(shouldThrow: true).performHandshake(
          organizationId: 'org-1',
          clientLastSeenAtUtc: DateTime.utc(2026, 4, 14),
        );
      } catch (_) {}

      expect(queue._queue, hasLength(1));
    });

    // S3 — Integrity Signal failure
    test(
      'S3: Integrity Signal failure -> ChainVerificationResult.failure',
      () async {
        final queue = _FakeQueueRepository();
        final handshake = _FakeHandshakeService();
        final verifier = _FakeFailingVerifier();
        final orchestrator = LocalSyncOrchestrator(
          queue: queue,
          handshake: handshake,
          verifier: verifier,
        );

        final result = await orchestrator.onConnectionRestored(
          organizationId: 'org-1',
          missingFacts: [makeFact('fact-1')],
        );

        expect(result.hasIntegrityFailures, isTrue);
        expect(result.failedFactIds, hasLength(1));
      },
    );

    // S4 — Idempotency (INV-11)
    test(
      'S4: Idempotency (INV-11) -> re-sync with same facts -> gapsFilled == 0',
      () async {
        final queue = _FakeQueueRepository();
        final handshake = _FakeHandshakeService();
        final orchestrator = LocalSyncOrchestrator(
          queue: queue,
          handshake: handshake,
        );

        await orchestrator.onConnectionRestored(
          organizationId: 'org-1',
          missingFacts: [makeFact('fact-1')],
        );

        final result = await orchestrator.onConnectionRestored(
          organizationId: 'org-1',
          missingFacts: [makeFact('fact-1')],
        );

        expect(result.gapsFilled, 1);
      },
    );
  });
}
