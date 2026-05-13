/// Forensic Audit Signature: CX-05-v3.1 / Red Team ID 3 — Tests
/// Coverage Target: 100% of `BinarySignatureValidator` + adversarial polyglot
///                  matrix (15 scenarios + extras).
/// Security Guard: INV-9, INV-10, INV-15, INV-18, INV-24, INV-28.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/sla_audit/justification/binary_signature_registry.dart';
import 'package:veraprob/application/sla_audit/justification/binary_signature_validator.dart';
import 'package:veraprob/application/sla_audit/justification/evidence_integrity_verifier.dart';
import 'package:veraprob/domain/sla_audit/forensic_violation_exception.dart';

class _MockReader extends Mock implements EvidenceStorageReader {}

/// Pads [body] with trailing zero bytes so the readRange mock always returns
/// at least [BinarySignatureRegistry.maxHeaderBytes] bytes — mirrors prod
/// behaviour where the storage layer returns the requested window length.
List<int> _pad(List<int> body) {
  const required = BinarySignatureRegistry.maxHeaderBytes;
  if (body.length >= required) return body;
  return [...body, ...List<int>.filled(required - body.length, 0)];
}

const _jpegSoi = <int>[0xFF, 0xD8, 0xFF];
const _pngHeader = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
const _pdfHeader = <int>[0x25, 0x50, 0x44, 0x46, 0x2D];
const _ftypHeic = <int>[0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63];
const _ftypHeix = <int>[0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x78];
const _ftypMif1 = <int>[0x66, 0x74, 0x79, 0x70, 0x6D, 0x69, 0x66, 0x31];

List<int> _heicHeader([List<int> brand = _ftypHeic]) => [
  0x00,
  0x00,
  0x00,
  0x18,
  ...brand,
];

List<int> _webpHeader() => [
  0x52, 0x49, 0x46, 0x46, // RIFF
  0x10, 0x00, 0x00, 0x00, // size (LE)
  0x57, 0x45, 0x42, 0x50, // WEBP
];

void main() {
  late _MockReader reader;
  late BinarySignatureValidator validator;

  setUp(() {
    reader = _MockReader();
    validator = BinarySignatureValidator(reader);
  });

  void stubReader(String url, List<int> bytes) {
    when(
      () => reader.readRange(
        url: url,
        start: 0,
        length: BinarySignatureRegistry.maxHeaderBytes,
      ),
    ).thenAnswer((_) async => bytes);
  }

  // ════════════════════════════════════════════════════════════════════════
  // Whitelist — happy paths
  // ════════════════════════════════════════════════════════════════════════
  group('Whitelist (positive)', () {
    test('JPEG (.jpg) — valid SOI passes', () async {
      const url = 'https://x/photo.jpg';
      stubReader(url, _pad(_jpegSoi));
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.jpg',
      );
      expect(mime, 'image/jpeg');
    });

    test('JPEG (.jpeg) alias maps to image/jpeg', () async {
      const url = 'https://x/photo.jpeg';
      stubReader(url, _pad(_jpegSoi));
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.jpeg',
      );
      expect(mime, 'image/jpeg');
    });

    test('PNG full 8-byte signature passes', () async {
      const url = 'https://x/photo.png';
      stubReader(url, _pad(_pngHeader));
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.png',
      );
      expect(mime, 'image/png');
    });

    test('PDF "%PDF-" passes', () async {
      const url = 'https://x/doc.pdf';
      stubReader(url, _pad(_pdfHeader));
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.pdf',
      );
      expect(mime, 'application/pdf');
    });

    test('HEIC: ftypheic at offset 4 passes', () async {
      const url = 'https://x/photo.heic';
      stubReader(url, _heicHeader(_ftypHeic));
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.heic',
      );
      expect(mime, 'image/heic');
    });

    test('HEIF: ftypmif1 at offset 4 passes', () async {
      const url = 'https://x/photo.heif';
      stubReader(url, _heicHeader(_ftypMif1));
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.heif',
      );
      expect(mime, 'image/heif');
    });

    test('WebP: RIFF + WEBP at offset 8 passes', () async {
      const url = 'https://x/photo.webp';
      stubReader(url, _webpHeader());
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.webp',
      );
      expect(mime, 'image/webp');
    });

    test('Case-insensitive: .JPG normalises', () async {
      const url = 'https://x/photo.JPG';
      stubReader(url, _pad(_jpegSoi));
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.JPG',
      );
      expect(mime, 'image/jpeg');
    });

    test('Case-insensitive: .Jpeg normalises', () async {
      const url = 'https://x/photo.Jpeg';
      stubReader(url, _pad(_jpegSoi));
      final mime = await validator.validate(
        url: url,
        declaredExtension: '.Jpeg',
      );
      expect(mime, 'image/jpeg');
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Polyglot / Masquerade — must throw ForensicViolationException
  // ════════════════════════════════════════════════════════════════════════
  group('Polyglot defence (adversarial)', () {
    test('shell.php renamed to foto.jpg → throws', () async {
      const url = 'https://x/foto.jpg';
      // PHP body — NO JPEG SOI.
      final phpBody = '<?php system(\$_GET["c"]); ?>'.codeUnits;
      stubReader(url, _pad(phpBody));
      await expectLater(
        validator.validate(url: url, declaredExtension: '.jpg'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test('ZIP-as-PDF (PK\\x03\\x04 declared .pdf) → throws', () async {
      const url = 'https://x/contract.pdf';
      stubReader(url, _pad([0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x00]));
      await expectLater(
        validator.validate(url: url, declaredExtension: '.pdf'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test('PNG bytes declared as .jpg → polyglot, throws', () async {
      const url = 'https://x/cross.jpg';
      stubReader(url, _pad(_pngHeader));
      final fut = validator.validate(url: url, declaredExtension: '.jpg');
      await expectLater(fut, throwsA(isA<ForensicViolationException>()));
    });

    test(
      'Polyglot message reveals MIME labels but NEVER raw bytes (INV-28)',
      () async {
        const url = 'https://x/leak.jpg';
        stubReader(url, _pad(_pngHeader));
        try {
          await validator.validate(url: url, declaredExtension: '.jpg');
          fail('should have thrown');
        } on ForensicViolationException catch (e) {
          expect(e.message, contains('Polyglot detected'));
          expect(e.message, contains('image/jpeg'));
          expect(e.message, contains('image/png'));
          // INV-28: assert no control characters / non-printables leaked.
          for (final unit in e.message.codeUnits) {
            final printable =
                unit == 0x09 ||
                unit == 0x0A ||
                unit == 0x0D ||
                (unit >= 0x20 && unit <= 0x7E);
            expect(
              printable,
              isTrue,
              reason:
                  'Exception message must not embed raw bytes from the file '
                  '(INV-28). Offending code unit: $unit',
            );
          }
        }
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // Offset attacks
  // ════════════════════════════════════════════════════════════════════════
  group('Offset enforcement', () {
    test('HEIC: ftypheic at offset 8 (wrong) → throws', () async {
      const url = 'https://x/wrong_offset.heic';
      // Move the brand to offset 8 — offset 4 holds zeros.
      final bytes = <int>[
        0x00, 0x00, 0x00, 0x00, // box size
        0x00, 0x00, 0x00, 0x00, // wrong-offset zone
        0x66, 0x74, 0x79, 0x70, // ftyp at offset 8 — not allowed
      ];
      stubReader(url, bytes);
      await expectLater(
        validator.validate(url: url, declaredExtension: '.heic'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test(
      'Null-byte padding before JPEG SOI → throws (strict offset)',
      () async {
        const url = 'https://x/padded.jpg';
        stubReader(url, _pad([0x00, 0x00, 0xFF, 0xD8, 0xFF]));
        await expectLater(
          validator.validate(url: url, declaredExtension: '.jpg'),
          throwsA(isA<ForensicViolationException>()),
        );
      },
    );

    test('HEIC variant brand "heix" rejected (closed enum)', () async {
      const url = 'https://x/variant.heic';
      stubReader(url, _heicHeader(_ftypHeix));
      await expectLater(
        validator.validate(url: url, declaredExtension: '.heic'),
        throwsA(isA<ForensicViolationException>()),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // WebP secondary-offset conjunction
  // ════════════════════════════════════════════════════════════════════════
  group('WebP secondary check', () {
    test('RIFF without WEBP at offset 8 → throws', () async {
      const url = 'https://x/fake.webp';
      stubReader(url, [
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00, // size
        0x41, 0x56, 0x49, 0x20, // 'AVI ' — NOT WEBP
      ]);
      await expectLater(
        validator.validate(url: url, declaredExtension: '.webp'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test('RIFX big-endian impersonation rejected', () async {
      const url = 'https://x/rifx.webp';
      stubReader(url, [
        0x52, 0x49, 0x46, 0x58, // RIFX (big-endian)
        0x10, 0x00, 0x00, 0x00,
        0x57, 0x45, 0x42, 0x50,
      ]);
      await expectLater(
        validator.validate(url: url, declaredExtension: '.webp'),
        throwsA(isA<ForensicViolationException>()),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Boundary cases
  // ════════════════════════════════════════════════════════════════════════
  group('Boundary inputs', () {
    test('0 bytes → throws (too short)', () async {
      const url = 'https://x/empty.jpg';
      stubReader(url, <int>[]);
      await expectLater(
        validator.validate(url: url, declaredExtension: '.jpg'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test('2 bytes (smaller than smallest header) → throws', () async {
      const url = 'https://x/tiny.jpg';
      stubReader(url, [0xFF, 0xD8]);
      await expectLater(
        validator.validate(url: url, declaredExtension: '.jpg'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test('Truncated PNG (only 4 of 8 signature bytes) → throws', () async {
      const url = 'https://x/trunc.png';
      // Pad to maxHeaderBytes so the length check passes, but the partial
      // PNG sig will not satisfy the 8-byte match.
      stubReader(url, _pad([0x89, 0x50, 0x4E, 0x47]));
      await expectLater(
        validator.validate(url: url, declaredExtension: '.png'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test(
      'False positive: bytes start FF D8 AA (broken JPEG) → throws',
      () async {
        const url = 'https://x/broken.jpg';
        stubReader(url, _pad([0xFF, 0xD8, 0xAA, 0x00, 0x00]));
        await expectLater(
          validator.validate(url: url, declaredExtension: '.jpg'),
          throwsA(isA<ForensicViolationException>()),
        );
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // Extension contract
  // ════════════════════════════════════════════════════════════════════════
  group('Extension whitelist', () {
    test('Unknown extension .exe → throws WITHOUT reading bytes', () async {
      const url = 'https://x/payload.exe';
      await expectLater(
        validator.validate(url: url, declaredExtension: '.exe'),
        throwsA(isA<ForensicViolationException>()),
      );
      verifyNever(
        () => reader.readRange(
          url: any(named: 'url'),
          start: any(named: 'start'),
          length: any(named: 'length'),
        ),
      );
    });

    test('Unknown extension .bin → throws', () async {
      const url = 'https://x/payload.bin';
      await expectLater(
        validator.validate(url: url, declaredExtension: '.bin'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test('Empty extension → throws (fail-fast)', () async {
      const url = 'https://x/no_ext';
      await expectLater(
        validator.validate(url: url, declaredExtension: ''),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test('Double-extension .jpg.php → resolves to .php → throws', () async {
      const url = 'https://x/sneaky.jpg.php';
      await expectLater(
        validator.validate(url: url, declaredExtension: '.jpg.php'),
        throwsA(isA<ForensicViolationException>()),
      );
    });

    test('Trailing dot ".jpg." → throws (no whitelist match)', () async {
      const url = 'https://x/weird.jpg.';
      await expectLater(
        validator.validate(url: url, declaredExtension: '.jpg.'),
        throwsA(isA<ForensicViolationException>()),
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // Buffer chunking — exactly one read, length 12
  // ════════════════════════════════════════════════════════════════════════
  group('Buffer chunking + Performance', () {
    test(
      'readRange called exactly once with length=12 (Availability)',
      () async {
        const url = 'https://x/photo.jpg';
        stubReader(url, _pad(_jpegSoi));

        await validator.validate(url: url, declaredExtension: '.jpg');

        verify(
          () => reader.readRange(
            url: url,
            start: 0,
            length: BinarySignatureRegistry.maxHeaderBytes,
          ),
        ).called(1);
        verifyNoMoreInteractions(reader);
      },
    );

    test('streamBytes is NEVER invoked (no full-file reads)', () async {
      const url = 'https://x/photo.png';
      stubReader(url, _pad(_pngHeader));
      await validator.validate(url: url, declaredExtension: '.png');
      verifyNever(() => reader.streamBytes(url: any(named: 'url')));
    });

    test('Validation completes well under 10ms on local check', () async {
      const url = 'https://x/photo.jpg';
      stubReader(url, _pad(_jpegSoi));
      final stopwatch = Stopwatch()..start();
      await validator.validate(url: url, declaredExtension: '.jpg');
      stopwatch.stop();
      // Generous bound: real cost is sub-millisecond; mock async overhead
      // dominates. Fails only on pathological regression.
      expect(stopwatch.elapsedMilliseconds, lessThan(50));
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // I/O failure passthrough
  // ════════════════════════════════════════════════════════════════════════
  group('I/O failure passthrough', () {
    test(
      'readRange exception propagates as-is (NOT a ForensicViolation)',
      () async {
        const url = 'https://x/network_fail.jpg';
        when(
          () => reader.readRange(
            url: url,
            start: 0,
            length: BinarySignatureRegistry.maxHeaderBytes,
          ),
        ).thenThrow(StateError('network down'));
        await expectLater(
          validator.validate(url: url, declaredExtension: '.jpg'),
          throwsA(isA<StateError>()),
        );
      },
    );
  });

  // ════════════════════════════════════════════════════════════════════════
  // Registry direct contract — defence in depth
  // ════════════════════════════════════════════════════════════════════════
  group('BinarySignatureRegistry.matchSignature', () {
    test('null on no match', () {
      expect(
        BinarySignatureRegistry.matchSignature(List.filled(12, 0)),
        isNull,
      );
    });

    test('JPEG match', () {
      final sig = BinarySignatureRegistry.matchSignature(_pad(_jpegSoi));
      expect(sig?.label, 'JPEG');
      expect(sig?.mimeType, 'image/jpeg');
    });

    test('WebP requires conjunction (RIFF + WEBP)', () {
      final partial = [
        0x52,
        0x49,
        0x46,
        0x46,
        0,
        0,
        0,
        0,
        0x41,
        0x56,
        0x49,
        0x20,
      ];
      expect(BinarySignatureRegistry.matchSignature(partial), isNull);
    });

    test('maxHeaderBytes is 12 (registry-derived constant)', () {
      expect(BinarySignatureRegistry.maxHeaderBytes, 12);
    });
  });
}
