/// Forensic Audit Signature: CX-05-v3.0 / Tests
/// Coverage Target: 100% de `_detectMimeFromBytes` (L107-164)
///                 + `_Semaphore.acquire`/`release` (L336-343) observáveis
///                 + Pass 1/Pass 2 (bypass forense obrigatório).
/// Security Guard: INV-9, INV-18, INV-24 Compliance Verified.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';

class MockEvidenceStorageReader extends Mock implements EvidenceStorageReader {}

/// Fake Random cravado: força `nextInt` a devolver sempre o mesmo offset
/// dentro do quintil band (usado p/ mirar probes específicos nos testes).
class _FixedRandom extends Fake implements Random {
  _FixedRandom(this._fixedValue);
  final int _fixedValue;

  @override
  int nextInt(int max) => _fixedValue < max ? _fixedValue : max - 1;
}

/// Envolve [payload] com ±64 bytes de ASCII printable (espaços). Garante
/// ratio ≈ 1.0 na janela adjacente de ±32 → Pass 2 confirma *high*.
List<int> _wrapWithPrintablePadding(
  String payload, {
  int padBytes = 64,
  int totalBytes = 1024,
}) {
  final body = [
    ...List<int>.filled(padBytes, 0x20),
    ...payload.codeUnits,
    ...List<int>.filled(padBytes, 0x20),
  ];
  if (totalBytes <= body.length) return body;
  return [...body, ...List<int>.filled(totalBytes - body.length, 0)];
}

/// Envolve [payload] com bytes NULL. Ratio = 0.0 na janela adjacente → Pass 2
/// suprime como binary noise (não lança).
List<int> _wrapWithBinaryNoise(
  String payload, {
  int padBytes = 64,
  int totalBytes = 1024,
}) {
  final body = [
    ...List<int>.filled(padBytes, 0),
    ...payload.codeUnits,
    ...List<int>.filled(padBytes, 0),
  ];
  if (totalBytes <= body.length) return body;
  return [...body, ...List<int>.filled(totalBytes - body.length, 0)];
}

const _pngHeader = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _jpegHeader = <int>[0xFF, 0xD8, 0xFF];
const _pdfHeader = <int>[0x25, 0x50, 0x44, 0x46];

void main() {
  late MockEvidenceStorageReader reader;

  setUp(() {
    reader = MockEvidenceStorageReader();
  });

  // ═══════════════════════════════════════════════════════════════════════
  // MIME Magic Bytes — 100% cobertura de `_detectMimeFromBytes` (L107-164)
  // ═══════════════════════════════════════════════════════════════════════
  group('MIME Magic Bytes', () {
    test(
      'DEVE retornar image/jpeg QUANDO bytes iniciam com FF D8 FF',
      () async {
        const url = 'https://storage.example.com/photo.jpg';
        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value([..._jpegHeader, ...List.filled(509, 0)]),
        );

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), equals('image/jpeg'));
      },
    );

    test(
      'DEVE retornar image/png QUANDO bytes iniciam com magic PNG completo',
      () async {
        const url = 'https://storage.example.com/photo.png';
        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value([..._pngHeader, ...List.filled(504, 0)]),
        );

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), equals('image/png'));
      },
    );

    test(
      'DEVE retornar application/pdf QUANDO bytes iniciam com %PDF (25 50 44 46)',
      () async {
        const url = 'https://storage.example.com/doc.pdf';
        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value([..._pdfHeader, ...List.filled(508, 0)]),
        );

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), equals('application/pdf'));
      },
    );

    test(
      'DEVE retornar image/heic QUANDO bytes 4-11 formam "ftypheic"',
      () async {
        const url = 'https://storage.example.com/photo.heic';
        final bytes = <int>[
          0, 0, 0, 0x18,
          0x66, 0x74, 0x79, 0x70, // 'ftyp'
          0x68, 0x65, 0x69, 0x63, // 'heic'
          ...List.filled(500, 0),
        ];
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), equals('image/heic'));
      },
    );

    test(
      'DEVE retornar image/heif QUANDO bytes 4-11 formam "ftypheif"',
      () async {
        const url = 'https://storage.example.com/photo.heif';
        final bytes = <int>[
          0, 0, 0, 0x18,
          0x66, 0x74, 0x79, 0x70, // 'ftyp'
          0x68, 0x65, 0x69, 0x66, // 'heif'
          ...List.filled(500, 0),
        ];
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), equals('image/heif'));
      },
    );

    test(
      'DEVE retornar image/webp QUANDO bytes contém "RIFF" + "WEBP" na posição 8',
      () async {
        const url = 'https://storage.example.com/photo.webp';
        final bytes = <int>[
          0x52, 0x49, 0x46, 0x46, // 'RIFF'
          0, 0, 0, 0, // chunk size
          0x57, 0x45, 0x42, 0x50, // 'WEBP'
          ...List.filled(500, 0),
        ];
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), equals('image/webp'));
      },
    );

    test(
      'DEVE retornar null QUANDO magic bytes não batem com formato conhecido',
      () async {
        const url = 'https://storage.example.com/unknown.bin';
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(List.filled(512, 0xAB)));

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), isNull);
      },
    );

    test(
      'DEVE retornar null QUANDO buffer tem 2 bytes (insuficiente p/ JPEG)',
      () async {
        const url = 'https://storage.example.com/truncated.bin';
        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value([0xFF, 0xD8]), // faltou 3º byte
        );

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), isNull);
      },
    );

    test(
      'DEVE retornar null QUANDO buffer tem 7 bytes (magic PNG incompleto)',
      () async {
        const url = 'https://storage.example.com/short-png.bin';
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(_pngHeader.take(7).toList()));

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), isNull);
      },
    );

    test(
      'DEVE retornar null QUANDO buffer < 12B impede match HEIC/HEIF/WebP',
      () async {
        const url = 'https://storage.example.com/short-heic.bin';
        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value(<int>[
            0, 0, 0, 0x18,
            0x66, 0x74, 0x79, 0x70, // 'ftyp'
            0x68, 0x65, 0x69, // 11 bytes — falta o 12º byte
          ]),
        );

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), isNull);
      },
    );

    test('DEVE retornar null (fail-safe) QUANDO buffer está vazio', () async {
      const url = 'https://storage.example.com/empty.bin';
      when(
        () => reader.streamBytes(url: url),
      ).thenAnswer((_) => Stream.fromIterable(<List<int>>[]));

      final analyzer = ContextualSignatureAnalyzer(reader);

      expect(await analyzer.detectMimeType(url), isNull);
    });

    test(
      'DEVE retornar null (fail-safe) QUANDO stream lança exceção I/O',
      () async {
        const url = 'https://storage.example.com/broken.bin';
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream<List<int>>.error(Exception('I/O failure')));

        final analyzer = ContextualSignatureAnalyzer(reader);

        expect(await analyzer.detectMimeType(url), isNull);
      },
    );

    test(
      'DEVE lançar DomainException QUANDO validateEvidence recebe MIME desconhecido',
      () async {
        const url = 'https://storage.example.com/unknown.bin';
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(List.filled(512, 0x00)));

        final analyzer = ContextualSignatureAnalyzer(reader);

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Invalid file type at evidence index 0'),
                contains('Allowed:'),
                contains('image/jpeg'),
                contains('application/pdf'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'DEVE reportar index correto QUANDO 2º arquivo tem MIME desconhecido',
      () async {
        const okUrl = 'https://storage.example.com/ok.jpg';
        const badUrl = 'https://storage.example.com/bad.xyz';
        when(() => reader.streamBytes(url: okUrl)).thenAnswer(
          (_) => Stream.value([..._jpegHeader, ...List.filled(509, 0)]),
        );
        when(
          () => reader.getContentLength(url: okUrl),
        ).thenAnswer((_) async => 512);
        when(
          () => reader.streamBytes(url: badUrl),
        ).thenAnswer((_) => Stream.value(List.filled(512, 0)));

        final analyzer = ContextualSignatureAnalyzer(reader);

        await expectLater(
          () => analyzer.validateEvidence([okUrl, badUrl]),
          throwsA(
            isA<DomainException>().having(
              (e) => e.message,
              'message',
              contains('evidence index 1'),
            ),
          ),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Semaphore — acquire/release observável (L331-347)
  // Nota: _concurrentProbeLimit=10 e buildProbes gera 7 → o branch de
  // enfileiramento (L336-338 e L342-343) é DEFENSIVO e não é exercido
  // pelo caminho público atual. Os testes abaixo cobrem o caminho quente
  // (contador >0 → decrementa; release → incrementa) e a garantia de
  // liberação via try/finally (não-deadlock em exceção).
  // ═══════════════════════════════════════════════════════════════════════
  group('Semaphore (10 simultâneos)', () {
    test(
      'DEVE liberar 7 probes sem deadlock QUANDO arquivo > 1MB (acquire/release felizes)',
      () async {
        const url = 'https://storage.example.com/large.png';
        const fileSize = 10 * 1024 * 1024;

        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value([..._pngHeader, ...List.filled(504, 0)]),
        );
        when(
          () => reader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);

        var totalProbes = 0;
        when(
          () => reader.readRange(
            url: url,
            start: any(named: 'start'),
            length: any(named: 'length'),
          ),
        ).thenAnswer((_) async {
          totalProbes++;
          return List<int>.filled(1024, 0);
        });

        final analyzer = ContextualSignatureAnalyzer(
          reader,
          random: Random(42),
        );

        await analyzer
            .validateEvidence([url])
            .timeout(const Duration(seconds: 5));

        expect(
          totalProbes,
          equals(7),
          reason: '1 Start + 5 Dynamic + 1 End = 7 probes',
        );
      },
    );

    test(
      'DEVE manter concorrência ≤ 10 QUANDO todos os probes disparam via Future.wait',
      () async {
        const url = 'https://storage.example.com/concurrent.png';
        const fileSize = 10 * 1024 * 1024;

        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value([..._pngHeader, ...List.filled(504, 0)]),
        );
        when(
          () => reader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);

        var active = 0;
        var maxObserved = 0;
        when(
          () => reader.readRange(
            url: url,
            start: any(named: 'start'),
            length: any(named: 'length'),
          ),
        ).thenAnswer((_) async {
          active++;
          if (active > maxObserved) maxObserved = active;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          active--;
          return List<int>.filled(1024, 0);
        });

        final analyzer = ContextualSignatureAnalyzer(reader, random: Random(7));

        await analyzer
            .validateEvidence([url])
            .timeout(const Duration(seconds: 5));

        expect(maxObserved, greaterThan(0));
        expect(
          maxObserved,
          lessThanOrEqualTo(10),
          reason: 'Semáforo deve limitar concorrência a 10 simultâneos',
        );
      },
    );

    test(
      'DEVE liberar semáforo QUANDO probe lança ForensicViolationException (try/finally — sem deadlock)',
      () async {
        const url = 'https://storage.example.com/malicious-large.png';
        const fileSize = 10 * 1024 * 1024;

        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value([..._pngHeader, ...List.filled(504, 0)]),
        );
        when(
          () => reader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);

        final malicious = _wrapWithPrintablePadding('<?php system("x"); ?>');
        when(
          () => reader.readRange(
            url: url,
            start: any(named: 'start'),
            length: any(named: 'length'),
          ),
        ).thenAnswer((_) async => malicious);

        final analyzer = ContextualSignatureAnalyzer(
          reader,
          random: Random(99),
        );

        await expectLater(
          () => analyzer
              .validateEvidence([url])
              .timeout(const Duration(seconds: 5)),
          throwsA(isA<ForensicViolationException>()),
        );
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Pass 1 + Pass 2 — Bypass forense obrigatório
  // ═══════════════════════════════════════════════════════════════════════
  group('Pass 1/Pass 2 — Inspeção forense obrigatória', () {
    test(
      'DEVE lançar ForensicViolationException high QUANDO payload tem padding printable (Pass 2 ≥ 0.60)',
      () async {
        const url = 'https://storage.example.com/payload.png';
        final buffer = _wrapWithPrintablePadding('<?php system("id"); ?>');
        final bytes = [..._pngHeader, ...buffer];

        when(
          () => reader.getContentLength(url: url),
        ).thenAnswer((_) async => bytes.length);
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(reader);

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<ForensicViolationException>()
                .having(
                  (e) => e.confidence,
                  'confidence',
                  ForensicConfidence.high,
                )
                .having((e) => e.evidenceUrl, 'evidenceUrl', url)
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('[Scanner: Contextual]'),
                    contains('Confirmed Malicious Signature'),
                    contains('Confidence: High'),
                    contains('Probe: Linear'),
                    contains('Offset'),
                  ),
                ),
          ),
        );
      },
    );

    test(
      'DEVE NÃO lançar QUANDO match "passthru(" tem padding de zeros (Pass 2 < 0.60 → binary noise)',
      () async {
        const url = 'https://storage.example.com/noise.png';
        final buffer = _wrapWithBinaryNoise('passthru(');
        final bytes = [..._pngHeader, ...buffer];

        when(
          () => reader.getContentLength(url: url),
        ).thenAnswer((_) async => bytes.length);
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(reader);

        await analyzer.validateEvidence([url]); // não deve lançar
      },
    );

    test(
      'DEVE NÃO lançar QUANDO JPEG pequeno é limpo (sem payload e sem match regex)',
      () async {
        const url = 'https://storage.example.com/clean.jpg';
        final bytes = [..._jpegHeader, ...List.filled(509, 0x00)];

        when(
          () => reader.getContentLength(url: url),
        ).thenAnswer((_) async => 512);
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(reader);

        await analyzer.validateEvidence([url]);
      },
    );

    test(
      'DEVE reportar "Dynamic Probe 3" + URL QUANDO hit ocorre na banda central de arquivo > 1MB',
      () async {
        const url = 'https://storage.example.com/large-hit.png';
        const fileSize = 10 * 1024 * 1024;
        const quintilSize = fileSize ~/ 5;
        const dynamicProbe3Start = 2 * quintilSize;

        when(() => reader.streamBytes(url: url)).thenAnswer(
          (_) => Stream.value([..._pngHeader, ...List.filled(504, 0)]),
        );
        when(
          () => reader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);

        when(
          () => reader.readRange(
            url: url,
            start: any(named: 'start'),
            length: any(named: 'length'),
          ),
        ).thenAnswer((inv) async {
          final start = inv.namedArguments[#start] as int;
          if (start == dynamicProbe3Start) {
            return _wrapWithPrintablePadding('<?php exec("x"); ?>');
          }
          return List<int>.filled(1024, 0);
        });

        final analyzer = ContextualSignatureAnalyzer(
          reader,
          random: _FixedRandom(0),
        );

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<ForensicViolationException>()
                .having((e) => e.evidenceUrl, 'evidenceUrl', url)
                .having(
                  (e) => e.confidence,
                  'confidence',
                  ForensicConfidence.high,
                )
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    contains('[Scanner: Contextual]'),
                    contains('Probe: Dynamic Probe 3'),
                    contains('<?php'),
                  ),
                ),
          ),
        );
      },
    );

    test(
      'DEVE reportar "Probe: Linear" QUANDO getContentLength falha e cai no linearScan',
      () async {
        const url = 'https://storage.example.com/unknown-size.png';
        final buffer = _wrapWithPrintablePadding('<?php echo "x"; ?>');
        final bytes = [..._pngHeader, ...buffer];

        when(
          () => reader.getContentLength(url: url),
        ).thenThrow(Exception('HEAD request failed'));
        when(
          () => reader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(reader);

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<ForensicViolationException>().having(
              (e) => e.message,
              'message',
              contains('Probe: Linear'),
            ),
          ),
        );
      },
    );
  });
}
