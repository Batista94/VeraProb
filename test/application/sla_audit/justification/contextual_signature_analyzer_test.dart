import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/justification/contextual_signature_analyzer.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';

class MockEvidenceStorageReader extends Mock implements EvidenceStorageReader {}

class _FixedRandom extends Fake implements Random {
  final int _fixedValue;
  _FixedRandom(this._fixedValue);

  @override
  int nextInt(int max) => _fixedValue < max ? _fixedValue : max - 1;
}

/// Builds a buffer where the regex match is surrounded by printable-ASCII
/// padding (spaces). Guarantees the ±32 byte adjacent window is ~1.0
/// printable → Pass 2 confirms high confidence.
List<int> _wrapWithPrintablePadding(
  String payload, {
  int padBytes = 64,
  int totalBytes = 1024,
}) {
  final prefix = List<int>.filled(padBytes, 0x20); // spaces
  final body = payload.codeUnits;
  final suffix = List<int>.filled(padBytes, 0x20);
  final prePadded = [...prefix, ...body, ...suffix];
  if (totalBytes > prePadded.length) {
    return [
      ...prePadded,
      ...List<int>.filled(totalBytes - prePadded.length, 0),
    ];
  }
  return prePadded;
}

/// Builds a buffer where the regex match is surrounded by ZERO bytes. The
/// ±32 byte adjacent window is all non-printable → Pass 2 suppresses as
/// binary noise (ratio = 0.0 << 0.60).
List<int> _wrapWithBinaryNoise(
  String payload, {
  int padBytes = 64,
  int totalBytes = 1024,
}) {
  final prefix = List<int>.filled(padBytes, 0);
  final body = payload.codeUnits;
  final suffix = List<int>.filled(padBytes, 0);
  final prePadded = [...prefix, ...body, ...suffix];
  if (totalBytes > prePadded.length) {
    return [
      ...prePadded,
      ...List<int>.filled(totalBytes - prePadded.length, 0),
    ];
  }
  return prePadded;
}

void main() {
  group('ContextualSignatureAnalyzer — Two-pass verdict (Regex + Printable Ratio)', () {
    late MockEvidenceStorageReader mockReader;

    setUp(() {
      mockReader = MockEvidenceStorageReader();
    });

    // ════════════════════════════════════════════════════════════════════
    // Pass 2 — Printable Ratio Verdict
    // ════════════════════════════════════════════════════════════════════

    test(
      'FP suppression: 1MB random binary with injected "passthru(" does NOT throw',
      () async {
        const url = 'https://storage.example.com/random-binary.png';
        const fileSize = 1024 * 1024; // exactly 1 MB → linear scan path
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

        final rng = Random(42);
        final randomBytes = List<int>.generate(
          fileSize - pngHeader.length,
          (_) => rng.nextInt(256),
        );
        // Inject literal "passthru(" at a deterministic offset in the random body.
        const injectionOffset = 500000;
        final payload = 'passthru('.codeUnits;
        for (var i = 0; i < payload.length; i++) {
          randomBytes[injectionOffset + i] = payload[i];
        }
        // Zero adjacent bytes to guarantee ratio < 0.60 (random would be ~0.38).
        for (var i = 1; i <= 32; i++) {
          randomBytes[injectionOffset - i] = 0x00;
          randomBytes[injectionOffset + payload.length + i - 1] = 0x00;
        }
        final fullBytes = [...pngHeader, ...randomBytes];

        when(
          () => mockReader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);
        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(fullBytes));

        final analyzer = ContextualSignatureAnalyzer(mockReader);

        // MUST NOT throw — adjacent ratio < 0.60 means binary noise.
        await analyzer.validateEvidence([url]);
      },
    );

    test(
      'Confirmed High: code-wrapped payload throws with confidence=high + Offset',
      () async {
        const url = 'https://storage.example.com/malicious.png';
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        const maliciousCode = '\nif (\$_GET["x"]) { passthru(\$_GET["x"]); }\n';
        final bytes = [...pngHeader, ...maliciousCode.codeUnits];

        when(
          () => mockReader.getContentLength(url: url),
        ).thenThrow(Exception('HEAD not supported — force linear scan'));
        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(mockReader);

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<ForensicViolationException>()
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
                    contains('Confirmed Malicious Signature'),
                    contains('Confidence: High'),
                    contains('Offset'),
                  ),
                ),
          ),
        );
      },
    );

    test(
      'Low confidence: binary-padded "passthru(" match does NOT throw',
      () async {
        const url = 'https://storage.example.com/noise-padded.png';
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        final noiseBuffer = _wrapWithBinaryNoise('passthru(');
        final bytes = [...pngHeader, ...noiseBuffer];

        when(
          () => mockReader.getContentLength(url: url),
        ).thenAnswer((_) async => bytes.length);
        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(mockReader);
        await analyzer.validateEvidence([url]);
      },
    );

    // ════════════════════════════════════════════════════════════════════
    // Pass 1 — Regex Coverage (payloads with real syntactic context)
    // ════════════════════════════════════════════════════════════════════

    test(
      'detects \'shell_exec("ls"); passthru("id");\' with high confidence',
      () async {
        const url = 'https://storage.example.com/mixed-payload.png';
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        final buffer = _wrapWithPrintablePadding(
          '\nshell_exec("ls"); passthru("id");\n',
        );
        final bytes = [...pngHeader, ...buffer];

        when(
          () => mockReader.getContentLength(url: url),
        ).thenAnswer((_) async => bytes.length);
        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(mockReader);

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<ForensicViolationException>().having(
              (e) => e.confidence,
              'confidence',
              ForensicConfidence.high,
            ),
          ),
        );
      },
    );

    test('detects \'; system("id"); exec(\' with high confidence', () async {
      const url = 'https://storage.example.com/system-payload.png';
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final buffer = _wrapWithPrintablePadding('; system("id"); exec(');
      final bytes = [...pngHeader, ...buffer];

      when(
        () => mockReader.getContentLength(url: url),
      ).thenAnswer((_) async => bytes.length);
      when(
        () => mockReader.streamBytes(url: url),
      ).thenAnswer((_) => Stream.value(bytes));

      final analyzer = ContextualSignatureAnalyzer(mockReader);

      await expectLater(
        () => analyzer.validateEvidence([url]),
        throwsA(
          isA<ForensicViolationException>()
              .having(
                (e) => e.confidence,
                'confidence',
                ForensicConfidence.high,
              )
              .having((e) => e.message, 'message', contains('system(')),
        ),
      );
    });

    test(
      'detects \' { shell_exec("ls -la"); }\' with high confidence',
      () async {
        const url = 'https://storage.example.com/braced-shell.png';
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        final buffer = _wrapWithPrintablePadding(' { shell_exec("ls -la"); }');
        final bytes = [...pngHeader, ...buffer];

        when(
          () => mockReader.getContentLength(url: url),
        ).thenAnswer((_) async => bytes.length);
        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(bytes));

        final analyzer = ContextualSignatureAnalyzer(mockReader);

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<ForensicViolationException>()
                .having(
                  (e) => e.confidence,
                  'confidence',
                  ForensicConfidence.high,
                )
                .having((e) => e.message, 'message', contains('shell_exec(')),
          ),
        );
      },
    );

    test('detects \'<?php echo "x"; ?>\' with high confidence', () async {
      const url = 'https://storage.example.com/php-payload.png';
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final buffer = _wrapWithPrintablePadding('<?php echo "x"; ?>');
      final bytes = [...pngHeader, ...buffer];

      when(
        () => mockReader.getContentLength(url: url),
      ).thenAnswer((_) async => bytes.length);
      when(
        () => mockReader.streamBytes(url: url),
      ).thenAnswer((_) => Stream.value(bytes));

      final analyzer = ContextualSignatureAnalyzer(mockReader);

      await expectLater(
        () => analyzer.validateEvidence([url]),
        throwsA(
          isA<ForensicViolationException>()
              .having(
                (e) => e.confidence,
                'confidence',
                ForensicConfidence.high,
              )
              .having((e) => e.message, 'message', contains('<?php')),
        ),
      );
    });

    // ════════════════════════════════════════════════════════════════════
    // N=7 Adaptive Jump Sampling (>1 MB triggers probe path)
    // ════════════════════════════════════════════════════════════════════

    test(
      'evasion: detects <?php payload at 27% offset in a 10MB file',
      () async {
        const url = 'https://storage.example.com/evasion-27pct.png';
        const fileSize = 10 * 1024 * 1024;
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

        const quintilSize = fileSize ~/ 5;
        const payloadOffset = (fileSize * 27) ~/ 100;
        const relativeOffset = payloadOffset - quintilSize;

        final analyzer = ContextualSignatureAnalyzer(
          mockReader,
          random: _FixedRandom(relativeOffset),
        );

        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(pngHeader + List.filled(504, 0)));
        when(
          () => mockReader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);

        when(
          () => mockReader.readRange(
            url: url,
            start: any(named: 'start'),
            length: any(named: 'length'),
          ),
        ).thenAnswer((inv) async {
          final start = inv.namedArguments[#start] as int;
          if (start == payloadOffset) {
            return _wrapWithPrintablePadding('<?php system("evasion"); ?>');
          }
          return List.filled(1024, 0);
        });

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<ForensicViolationException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('[Scanner: Contextual]'),
                contains('Dynamic Probe 2'),
                contains('<?php'),
                contains('Offset ${payloadOffset + 64}'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'stress: aborts immediately when readRange receives non-206 (no OOM)',
      () async {
        const url = 'https://storage.example.com/huge-500mb.png';
        const fileSize = 500 * 1024 * 1024;
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

        final analyzer = ContextualSignatureAnalyzer(mockReader);

        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(pngHeader + List.filled(504, 0)));
        when(
          () => mockReader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);

        when(
          () => mockReader.readRange(
            url: url,
            start: any(named: 'start'),
            length: any(named: 'length'),
          ),
        ).thenThrow(
          Exception(
            'Range request not honored: expected 206 Partial Content but got 200.',
          ),
        );

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('206'),
            ),
          ),
        );
      },
    );

    test('naming: ContextualSignatureAnalyzer has self-describing name', () {
      final analyzer = ContextualSignatureAnalyzer(mockReader);
      expect(
        analyzer,
        isA<ContextualSignatureAnalyzer>(),
        reason:
            'Class name must reflect its purpose: contextual, signature, analyzer',
      );
    });

    test(
      'detects <?php payload at 50% (Dynamic Probe 3) of a 10MB file',
      () async {
        const url = 'https://storage.example.com/large-evidence.png';
        const fileSize = 10 * 1024 * 1024;
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

        const quintilSize = fileSize ~/ 5;
        const bandStart = 2 * quintilSize;
        const probeOffset = bandStart;

        final analyzer = ContextualSignatureAnalyzer(
          mockReader,
          random: _FixedRandom(0),
        );

        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(pngHeader + List.filled(504, 0)));
        when(
          () => mockReader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);

        when(
          () => mockReader.readRange(
            url: url,
            start: any(named: 'start'),
            length: any(named: 'length'),
          ),
        ).thenAnswer((inv) async {
          final start = inv.namedArguments[#start] as int;
          if (start == probeOffset) {
            return _wrapWithPrintablePadding('<?php system("id"); ?>');
          }
          return List.filled(1024, 0);
        });

        await expectLater(
          () => analyzer.validateEvidence([url]),
          throwsA(
            isA<ForensicViolationException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('[Scanner: Contextual]'),
                contains('Dynamic Probe 3'),
                contains('<?php'),
                contains('Offset ${probeOffset + 64}'),
              ),
            ),
          ),
        );
      },
    );

    test('falls back to linear scan if getContentLength throws', () async {
      const url = 'https://storage.example.com/unknown-size.png';
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
      final buffer = _wrapWithPrintablePadding('<?php echo "x"; ?>');
      final bytes = [...pngHeader, ...buffer];

      final analyzer = ContextualSignatureAnalyzer(mockReader);

      when(
        () => mockReader.getContentLength(url: url),
      ).thenThrow(Exception('HEAD request failed'));

      when(
        () => mockReader.streamBytes(url: url),
      ).thenAnswer((_) => Stream.value(bytes));

      await expectLater(
        () => analyzer.validateEvidence([url]),
        throwsA(
          isA<ForensicViolationException>().having(
            (e) => e.message,
            'message',
            contains('Linear'),
          ),
        ),
      );
    });

    test('detects base64_decode in Start probe of a 2MB file', () async {
      const url = 'https://storage.example.com/obfuscated.png';
      const fileSize = 2 * 1024 * 1024;
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

      final analyzer = ContextualSignatureAnalyzer(mockReader);

      when(
        () => mockReader.streamBytes(url: url),
      ).thenAnswer((_) => Stream.value(pngHeader + List.filled(504, 0)));
      when(
        () => mockReader.getContentLength(url: url),
      ).thenAnswer((_) async => fileSize);

      when(
        () => mockReader.readRange(
          url: url,
          start: any(named: 'start'),
          length: any(named: 'length'),
        ),
      ).thenAnswer((inv) async {
        final start = inv.namedArguments[#start] as int;
        if (start == 0) {
          return [
            ...pngHeader,
            ..._wrapWithPrintablePadding('base64_decode("obfuscated")'),
          ];
        }
        return List.filled(1024, 0);
      });

      await expectLater(
        () => analyzer.validateEvidence([url]),
        throwsA(
          isA<ForensicViolationException>().having(
            (e) => e.message,
            'message',
            contains('base64_decode('),
          ),
        ),
      );
    });

    // ════════════════════════════════════════════════════════════════════
    // MIME Whitelist (DomainException, NOT ForensicViolationException)
    // ════════════════════════════════════════════════════════════════════

    test('MIME rejection: unsupported format throws DomainException', () async {
      const url = 'https://storage.example.com/unknown.bin';
      final analyzer = ContextualSignatureAnalyzer(mockReader);

      when(
        () => mockReader.streamBytes(url: url),
      ).thenAnswer((_) => Stream.value(List.filled(512, 0x00)));

      await expectLater(
        () => analyzer.validateEvidence([url]),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('Invalid file type') &&
                e.toString().contains('Allowed:'),
          ),
        ),
      );
    });
  });
}
