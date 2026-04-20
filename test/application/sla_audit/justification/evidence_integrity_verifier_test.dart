import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/concurrency/smart_concurrency_governor.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';

class MockEvidenceStorageReader extends Mock implements EvidenceStorageReader {}

class _CountingGovernor extends SmartConcurrencyGovernor {
  int callCount = 0;
  int peakInFlight = 0;

  _CountingGovernor({super.maxConcurrent = 10});

  @override
  Future<T> run<T>(ConcurrencyTask<T> task) {
    callCount++;
    if (inFlightCount + 1 > peakInFlight) peakInFlight = inFlightCount + 1;
    return super.run(task);
  }
}

String _sha256Of(List<int> bytes) => sha256.convert(bytes).toString();

Stream<List<int>> _streamChunks(
  List<int> bytes, {
  int chunkSize = 32 * 1024,
}) async* {
  for (var i = 0; i < bytes.length; i += chunkSize) {
    final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
    yield bytes.sublist(i, end);
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Stream<List<int>>.empty());
  });

  group('EvidenceIntegrityVerifier.verifyAll - INV-9 Evidence Sealing', () {
    late MockEvidenceStorageReader reader;

    setUp(() {
      reader = MockEvidenceStorageReader();
    });

    test('DEVE retornar lista vazia QUANDO todos os hashes batem', () async {
      final payloadA = utf8.encode('evidence-A');
      final payloadB = utf8.encode('evidence-B');
      final hashA = _sha256Of(payloadA);
      final hashB = _sha256Of(payloadB);

      when(
        () => reader.streamBytes(url: 'url-a'),
      ).thenAnswer((_) => _streamChunks(payloadA));
      when(
        () => reader.streamBytes(url: 'url-b'),
      ).thenAnswer((_) => _streamChunks(payloadB));

      final verifier = EvidenceIntegrityVerifier(reader);
      final mismatches = await verifier.verifyAll(
        evidenceUrls: ['url-a', 'url-b'],
        declaredHashes: [hashA, hashB],
      );

      expect(mismatches, isEmpty);
    });

    test(
      'DEVE marcar índice QUANDO hash computado difere do declarado',
      () async {
        final good = utf8.encode('intact');
        final tampered = utf8.encode('tampered-bytes');
        final declaredGood = _sha256Of(good);
        final declaredBogus = _sha256Of(utf8.encode('original-expected'));

        when(
          () => reader.streamBytes(url: 'ok'),
        ).thenAnswer((_) => _streamChunks(good));
        when(
          () => reader.streamBytes(url: 'bad'),
        ).thenAnswer((_) => _streamChunks(tampered));

        final verifier = EvidenceIntegrityVerifier(reader);
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['ok', 'bad'],
          declaredHashes: [declaredGood, declaredBogus],
        );

        expect(mismatches, [1]);
      },
    );

    test('DEVE retornar lista vazia QUANDO input é vazio', () async {
      final verifier = EvidenceIntegrityVerifier(reader);
      final mismatches = await verifier.verifyAll(
        evidenceUrls: const [],
        declaredHashes: const [],
      );

      expect(mismatches, isEmpty);
      verifyZeroInteractions(reader);
    });

    test('DEVE preservar ordem dos índices com múltiplos mismatches', () async {
      final payload = utf8.encode('payload');
      final correct = _sha256Of(payload);
      final wrong = _sha256Of(utf8.encode('nope'));

      for (final url in ['u0', 'u1', 'u2', 'u3']) {
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => _streamChunks(payload));
      }

      final verifier = EvidenceIntegrityVerifier(reader);
      final mismatches = await verifier.verifyAll(
        evidenceUrls: ['u0', 'u1', 'u2', 'u3'],
        declaredHashes: [correct, wrong, correct, wrong],
      );

      expect(mismatches, [1, 3]);
    });
  });

  group('_computeStreamingSha256 - chunk variance & large files', () {
    late MockEvidenceStorageReader reader;

    setUp(() => reader = MockEvidenceStorageReader());

    test(
      'DEVE produzir hash idêntico QUANDO chunks têm tamanhos variados',
      () async {
        final payload = utf8.encode(
          'the quick brown fox jumps over the lazy dog',
        );
        final declared = _sha256Of(payload);

        when(
          () => reader.streamBytes(url: 'tiny-chunks'),
        ).thenAnswer((_) => _streamChunks(payload, chunkSize: 1));
        when(
          () => reader.streamBytes(url: 'mid-chunks'),
        ).thenAnswer((_) => _streamChunks(payload, chunkSize: 7));
        when(
          () => reader.streamBytes(url: 'one-chunk'),
        ).thenAnswer((_) => _streamChunks(payload, chunkSize: 1024));

        final verifier = EvidenceIntegrityVerifier(reader);
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['tiny-chunks', 'mid-chunks', 'one-chunk'],
          declaredHashes: [declared, declared, declared],
        );

        expect(mismatches, isEmpty);
      },
    );

    test(
      'DEVE processar arquivo grande QUANDO streaming em chunks 32KB (memória constante)',
      () async {
        final large = List<int>.generate(1024 * 1024, (i) => i % 251); // 1 MiB
        final declared = _sha256Of(large);

        when(
          () => reader.streamBytes(url: 'large'),
        ).thenAnswer((_) => _streamChunks(large, chunkSize: 32 * 1024));

        final verifier = EvidenceIntegrityVerifier(reader);
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['large'],
          declaredHashes: [declared],
        );

        expect(mismatches, isEmpty);
      },
    );

    test('DEVE tratar arquivo vazio QUANDO stream não emite bytes', () async {
      final declaredEmpty = _sha256Of(const []);

      when(
        () => reader.streamBytes(url: 'empty'),
      ).thenAnswer((_) => const Stream<List<int>>.empty());

      final verifier = EvidenceIntegrityVerifier(reader);
      final mismatches = await verifier.verifyAll(
        evidenceUrls: ['empty'],
        declaredHashes: [declaredEmpty],
      );

      expect(mismatches, isEmpty);
    });

    test(
      'DEVE falhar e marcar mismatch QUANDO stream corrompe com erro',
      () async {
        final declared = _sha256Of(utf8.encode('anything'));

        when(() => reader.streamBytes(url: 'broken')).thenAnswer(
          (_) => Stream<List<int>>.error(
            StateError('stream corrupted mid-transfer'),
          ),
        );

        final verifier = EvidenceIntegrityVerifier(reader);
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['broken'],
          declaredHashes: [declared],
        );

        expect(mismatches, [0]);
        verify(
          () => reader.streamBytes(url: 'broken'),
        ).called(EvidenceIntegrityVerifier.maxRetries);
      },
    );
  });

  group('Retry policy - exponential backoff (INV-10, INV-18)', () {
    late MockEvidenceStorageReader reader;

    setUp(() => reader = MockEvidenceStorageReader());

    test(
      'DEVE recuperar QUANDO falha duas vezes e sucesso na terceira',
      () async {
        final payload = utf8.encode('flaky-but-real');
        final declared = _sha256Of(payload);

        var attempt = 0;
        when(() => reader.streamBytes(url: 'flaky')).thenAnswer((_) {
          final current = attempt++;
          if (current < 2) {
            return Stream<List<int>>.error(
              Exception('transient network failure attempt=$current'),
            );
          }
          return _streamChunks(payload);
        });

        final verifier = EvidenceIntegrityVerifier(reader);
        final sw = Stopwatch()..start();
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['flaky'],
          declaredHashes: [declared],
        );
        sw.stop();

        expect(mismatches, isEmpty);
        verify(() => reader.streamBytes(url: 'flaky')).called(3);
        // Backoff: 500ms after attempt-0, 1000ms after attempt-1 → ~1500ms floor.
        expect(
          sw.elapsedMilliseconds,
          greaterThanOrEqualTo(1400),
          reason: 'Exponential backoff must apply 500ms + 1s between retries',
        );
      },
    );

    test(
      'DEVE marcar mismatch QUANDO retries se esgotam (3 falhas consecutivas)',
      () async {
        final declared = _sha256Of(utf8.encode('never-arrives'));

        when(() => reader.streamBytes(url: 'dead')).thenAnswer(
          (_) => Stream<List<int>>.error(Exception('permanent failure')),
        );

        final verifier = EvidenceIntegrityVerifier(reader);
        final sw = Stopwatch()..start();
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['dead'],
          declaredHashes: [declared],
        );
        sw.stop();

        expect(mismatches, [0]);
        verify(
          () => reader.streamBytes(url: 'dead'),
        ).called(EvidenceIntegrityVerifier.maxRetries);
        expect(
          sw.elapsedMilliseconds,
          greaterThanOrEqualTo(1400),
          reason: 'Two backoff windows must elapse before returning null',
        );
      },
    );

    test(
      'DEVE respeitar constantes forenses maxRetries=3 e baseDelay=500ms',
      () {
        expect(EvidenceIntegrityVerifier.maxRetries, 3);
        expect(
          EvidenceIntegrityVerifier.baseDelay,
          const Duration(milliseconds: 500),
        );
      },
    );
  });

  group('TOCTOU — file alteration between retry attempts', () {
    late MockEvidenceStorageReader reader;

    setUp(() => reader = MockEvidenceStorageReader());

    test(
      'DEVE marcar mismatch QUANDO bytes mudam entre tentativas (race alter.)',
      () async {
        // Simula: client declarou hash de payload-A.
        // 1ª tentativa falha (stream erro).
        // 2ª tentativa retorna payload-B (arquivo foi trocado entre HEAD e stream).
        // Hash computado (B) ≠ declarado (A) → mismatch preservado, sem falso-positivo.
        final originalPayload = utf8.encode('original-evidence-bytes');
        final mutatedPayload = utf8.encode('swapped-bytes-after-toctou');
        final declaredOriginal = _sha256Of(originalPayload);

        var attempt = 0;
        when(() => reader.streamBytes(url: 'toctou')).thenAnswer((_) {
          final current = attempt++;
          if (current == 0) {
            return Stream<List<int>>.error(StateError('transient'));
          }
          return _streamChunks(mutatedPayload);
        });

        final verifier = EvidenceIntegrityVerifier(reader);
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['toctou'],
          declaredHashes: [declaredOriginal],
        );

        expect(mismatches, [0]);
        expect(attempt, greaterThanOrEqualTo(2));
      },
    );

    test(
      'DEVE tratar como mismatch QUANDO retry retorna payload de tamanho diferente',
      () async {
        final declared = _sha256Of(utf8.encode('expected-payload'));

        var attempt = 0;
        when(() => reader.streamBytes(url: 'shrunk')).thenAnswer((_) {
          if (attempt++ == 0) {
            return Stream<List<int>>.error(Exception('fail'));
          }
          return _streamChunks(utf8.encode('x')); // bytes truncados
        });

        final verifier = EvidenceIntegrityVerifier(reader);
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['shrunk'],
          declaredHashes: [declared],
        );

        expect(mismatches, [0]);
      },
    );
  });

  group('SmartConcurrencyGovernor integration', () {
    late MockEvidenceStorageReader reader;

    setUp(() => reader = MockEvidenceStorageReader());

    test(
      'DEVE rodar cada verificação sob o governor QUANDO fornecido',
      () async {
        final payload = utf8.encode('governed');
        final declared = _sha256Of(payload);

        when(
          () => reader.streamBytes(url: any(named: 'url')),
        ).thenAnswer((_) => _streamChunks(payload));

        final governor = _CountingGovernor(maxConcurrent: 2);
        final verifier = EvidenceIntegrityVerifier(reader, governor: governor);

        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['a', 'b', 'c'],
          declaredHashes: [declared, declared, declared],
        );

        expect(mismatches, isEmpty);
        expect(governor.callCount, 3);
      },
    );

    test(
      'DEVE operar sem governor QUANDO não fornecido (fallback direto)',
      () async {
        final payload = utf8.encode('ungoverned');
        final declared = _sha256Of(payload);

        when(
          () => reader.streamBytes(url: 'solo'),
        ).thenAnswer((_) => _streamChunks(payload));

        final verifier = EvidenceIntegrityVerifier(reader);
        final mismatches = await verifier.verifyAll(
          evidenceUrls: ['solo'],
          declaredHashes: [declared],
        );

        expect(mismatches, isEmpty);
      },
    );

    test('DEVE liberar slot do governor QUANDO task falha com erro', () async {
      when(
        () => reader.streamBytes(url: 'boom'),
      ).thenAnswer((_) => Stream<List<int>>.error(Exception('explode')));

      final governor = _CountingGovernor(maxConcurrent: 1);
      final verifier = EvidenceIntegrityVerifier(reader, governor: governor);

      await verifier.verifyAll(
        evidenceUrls: ['boom'],
        declaredHashes: [_sha256Of(utf8.encode('x'))],
      );

      // Após falhar (3 tentativas), o slot deve estar livre.
      expect(governor.inFlightCount, 0);
      expect(governor.queuedCount, 0);
    });
  });
}
