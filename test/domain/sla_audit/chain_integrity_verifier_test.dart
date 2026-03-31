import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/canonical_fact.dart';
import 'package:veraprob/domain/sla_audit/ingestion_integrity_flag.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/chain_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/local_fact_queue/pending_fact.dart';

void main() {
  const verifier = ChainIntegrityVerifier();

  PendingFact makePending({int seq = 1}) {
    final fact = CanonicalFact.create(
      organizationId: 'org-1',
      rawPayloadId: 'raw-$seq',
      deviceId: 'DEV-$seq',
      sourceAdapter: 'SASCAR_V1',
      receivedAtUtc: DateTime.utc(2026, 5, 1, 10, seq, 0),
      gpsTimestamp: DateTime.utc(2026, 5, 1, 9, seq, 0),
      lat: -23.0,
      lng: -46.0,
      integrityFlag: IngestionIntegrityFlag.ok,
    );
    return PendingFact.fromIncomingFact(fact, localSequence: seq);
  }

  PendingFact tamper(PendingFact p) => PendingFact.reconstitute(
    factId: p.factId,
    organizationId: p.organizationId,
    contentHash: 'aaaa' * 16, // wrong hash
    factPayloadJson: p.factPayloadJson,
    receivedAtUtc: p.receivedAtUtc,
    queuedAtUtc: p.queuedAtUtc,
    syncStatus: p.syncStatus,
    localSequence: p.localSequence,
    retryCount: p.retryCount,
  );

  group('ChainIntegrityVerifier.verify()', () {
    test('empty list returns valid result', () {
      final result = verifier.verify([]);
      expect(result.isValid, isTrue);
      expect(result.firstFailureIndex, isNull);
    });

    test('single intact fact passes', () {
      final result = verifier.verify([makePending()]);
      expect(result.isValid, isTrue);
    });

    test('multiple intact facts all pass', () {
      final facts = [
        makePending(seq: 1),
        makePending(seq: 2),
        makePending(seq: 3),
      ];
      final result = verifier.verify(facts);
      expect(result.isValid, isTrue);
    });

    test('detects single tampered fact', () {
      final bad = tamper(makePending());
      final result = verifier.verify([bad]);
      expect(result.isValid, isFalse);
      expect(result.firstFailureIndex, 0);
      expect(result.firstFailingFactId, bad.factId);
    });

    test('reports index of first tampered fact in mixed list', () {
      final good1 = makePending(seq: 1);
      final good2 = makePending(seq: 2);
      final bad = tamper(makePending(seq: 3));
      final good4 = makePending(seq: 4);

      final result = verifier.verify([good1, good2, bad, good4]);

      expect(result.isValid, isFalse);
      expect(result.firstFailureIndex, 2);
      expect(result.firstFailingFactId, bad.factId);
    });

    test('stops at first failure — does not inspect subsequent facts', () {
      final bad1 = tamper(makePending(seq: 1));
      final bad2 = tamper(makePending(seq: 2));

      final result = verifier.verify([bad1, bad2]);

      // Only the first failure is reported.
      expect(result.firstFailureIndex, 0);
      expect(result.firstFailingFactId, bad1.factId);
    });
  });
}
