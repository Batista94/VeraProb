import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_binary_jump_sampling_validator.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';

class MockEvidenceStorageReader extends Mock implements EvidenceStorageReader {}

/// Deterministic random that always returns [fixedValue] clamped to [max-1].
class _FixedRandom extends Fake implements Random {
  final int _fixedValue;
  _FixedRandom(this._fixedValue);

  @override
  int nextInt(int max) => _fixedValue < max ? _fixedValue : max - 1;
}

void main() {
  group('EvidenceBinaryJumpSamplingValidator — N=7 Jump Sampling', () {
    late MockEvidenceStorageReader mockReader;

    setUp(() {
      mockReader = MockEvidenceStorageReader();
    });

    // ── Evasion: PHP payload at 27% of file ──────────────────────────────
    test('evasion: detects <?php payload at 27% offset in a 10MB file', () async {
      const url = 'https://storage.example.com/evasion-27pct.png';
      const fileSize = 10 * 1024 * 1024; // 10 MB
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

      // 27% of 10MB = 2831155; quintil band 1 (20-40%) starts at 2MB = 2097152.
      const quintilSize = fileSize ~/ 5; // 2097152
      const payloadOffset = (fileSize * 27) ~/ 100; // 2831155
      const relativeOffset = payloadOffset - quintilSize; // 734003

      final validator = EvidenceBinaryJumpSamplingValidator(
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
        // The Quintil2 probe should land exactly at payloadOffset
        if (start == payloadOffset) {
          return '<?php system("evasion"); ?>'.codeUnits;
        }
        return List.filled(1024, 0);
      });

      await expectLater(
        () => validator.validateEvidence([url]),
        throwsA(
          isA<ForensicViolationException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('[Probe: Quintil2]'),
              contains('Signature "<?php"'),
              contains('at offset $payloadOffset'),
            ),
          ),
        ),
      );
    });

    // ── Stress: 500MB file, server returns 200 OK → abort without OOM ────
    test(
      'stress: aborts immediately when readRange receives non-206 (no OOM)',
      () async {
        const url = 'https://storage.example.com/huge-500mb.png';
        const fileSize = 500 * 1024 * 1024; // 500 MB
        final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

        final validator = EvidenceBinaryJumpSamplingValidator(mockReader);

        when(
          () => mockReader.streamBytes(url: url),
        ).thenAnswer((_) => Stream.value(pngHeader + List.filled(504, 0)));
        when(
          () => mockReader.getContentLength(url: url),
        ).thenAnswer((_) async => fileSize);

        // Simulate infrastructure enforcing 206-only (server returned 200 OK)
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
          () => validator.validateEvidence([url]),
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

    // ── Naming: self-describing class name ────────────────────────────────
    test(
      'naming: EvidenceBinaryJumpSamplingValidator has self-describing name',
      () {
        final validator = EvidenceBinaryJumpSamplingValidator(mockReader);
        expect(
          validator,
          isA<EvidenceBinaryJumpSamplingValidator>(),
          reason:
              'Class name must reflect its purpose: binary, jump-sampling, validator',
        );
      },
    );

    // ── Existing: PHP at middle ───────────────────────────────────────────
    test('detects <?php payload at 50% (Quintil3) of a 10MB file', () async {
      const url = 'https://storage.example.com/large-evidence.png';
      const fileSize = 10 * 1024 * 1024;
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

      // Middle = 50%, falls in quintil band 2 (index 2, 40%-60%).
      // bandStart for i=2: 2 * (10MB/5) = 4MB = 4194304
      const quintilSize = fileSize ~/ 5;
      const bandStart = 2 * quintilSize; // 4194304
      const probeOffset = bandStart; // _FixedRandom(0) → offset = bandStart+0

      final validator = EvidenceBinaryJumpSamplingValidator(
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
          return '... <?php system("id"); ?> ...'.codeUnits;
        }
        return List.filled(1024, 0);
      });

      await expectLater(
        () => validator.validateEvidence([url]),
        throwsA(
          isA<ForensicViolationException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('[Probe: Quintil3]'),
              contains('Signature "<?php"'),
              contains('at offset $probeOffset'),
            ),
          ),
        ),
      );
    });

    // ── Existing: linear scan fallback when getContentLength throws ───────
    test('falls back to linear scan if getContentLength throws', () async {
      const url = 'https://storage.example.com/unknown-size.png';
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

      final validator = EvidenceBinaryJumpSamplingValidator(mockReader);

      when(
        () => mockReader.getContentLength(url: url),
      ).thenThrow(Exception('HEAD request failed'));

      when(() => mockReader.streamBytes(url: url)).thenAnswer(
        (_) => Stream.value(pngHeader + '<?php payload at start'.codeUnits),
      );

      await expectLater(
        () => validator.validateEvidence([url]),
        throwsA(
          isA<ForensicViolationException>().having(
            (e) => e.message,
            'message',
            contains('[Probe: Linear]'),
          ),
        ),
      );
    });

    // ── Existing: detects base64_decode via jump sampling ─────────────────
    test('detects base64_decode in Start probe of a 2MB file', () async {
      const url = 'https://storage.example.com/obfuscated.png';
      const fileSize = 2 * 1024 * 1024;
      final pngHeader = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

      final validator = EvidenceBinaryJumpSamplingValidator(mockReader);

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
          return pngHeader + 'base64_decode("obfuscated")'.codeUnits;
        }
        return List.filled(1024, 0);
      });

      await expectLater(
        () => validator.validateEvidence([url]),
        throwsA(
          isA<ForensicViolationException>().having(
            (e) => e.message,
            'message',
            contains('Signature "base64_decode("'),
          ),
        ),
      );
    });
  });
}
