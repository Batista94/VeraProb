import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/integrity_exception.dart';
import 'package:veraprob/domain/shared/security_assertion_service.dart';

void main() {
  group('SecurityAssertionService', () {
    group('assertPlainTextMagicBytes', () {
      test('Accepts valid CSV text bytes', () {
        final bytes = 'col1,col2\nval1,val2'.codeUnits;
        expect(
          () => SecurityAssertionService.assertPlainTextMagicBytes(bytes),
          returnsNormally,
        );
      });

      test('Rejects empty file', () {
        expect(
          () => SecurityAssertionService.assertPlainTextMagicBytes([]),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('File is empty'),
            ),
          ),
        );
      });

      test('Hacking/Adverse: Rejects PDF files (MIME Sniffing)', () {
        // %PDF
        final bytes = [0x25, 0x50, 0x44, 0x46, 0x2D, 0x31, 0x2E, 0x34];
        expect(
          () => SecurityAssertionService.assertPlainTextMagicBytes(bytes),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Detected PDF'),
            ),
          ),
        );
      });

      test('Hacking/Adverse: Rejects ZIP/XLSX files (MIME Sniffing)', () {
        // PK
        final bytes = [0x50, 0x4B, 0x03, 0x04, 0x14, 0x00, 0x06, 0x00];
        expect(
          () => SecurityAssertionService.assertPlainTextMagicBytes(bytes),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Detected ZIP/Archive'),
            ),
          ),
        );
      });

      test('Hacking/Adverse: Rejects EXE/MZ files (MIME Sniffing)', () {
        // MZ
        final bytes = [0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00];
        expect(
          () => SecurityAssertionService.assertPlainTextMagicBytes(bytes),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Detected Executable'),
            ),
          ),
        );
      });
    });

    group('assertNoCsvInjection', () {
      test('Accepts normal text', () {
        expect(
          SecurityAssertionService.assertNoCsvInjection(
            'Normal Value',
            'field',
          ),
          'Normal Value',
        );
      });

      test('Accepts empty or whitespace', () {
        expect(
          SecurityAssertionService.assertNoCsvInjection('   ', 'field'),
          '   ',
        );
      });

      test('Hacking/Adverse: Rejects Formula Injection =', () {
        expect(
          () => SecurityAssertionService.assertNoCsvInjection(
            '=cmd|/C!',
            'field',
          ),
          throwsA(
            isA<IntegrityException>().having(
              (e) => e.message,
              'message',
              contains('Formula injection detected'),
            ),
          ),
        );
      });

      test('Hacking/Adverse: Rejects Formula Injection +', () {
        expect(
          () => SecurityAssertionService.assertNoCsvInjection(
            '+1+cmd|/C!',
            'field',
          ),
          throwsA(isA<IntegrityException>()),
        );
      });

      test('Hacking/Adverse: Rejects Formula Injection -', () {
        expect(
          () => SecurityAssertionService.assertNoCsvInjection(
            '-1+cmd|/C!',
            'field',
          ),
          throwsA(isA<IntegrityException>()),
        );
      });

      test('Hacking/Adverse: Rejects Formula Injection @', () {
        expect(
          () => SecurityAssertionService.assertNoCsvInjection(
            '@SUM(1,1)',
            'field',
          ),
          throwsA(isA<IntegrityException>()),
        );
      });
    });

    group('sanitizeHtml', () {
      test('Accepts normal text', () {
        expect(
          SecurityAssertionService.sanitizeHtml('Normal Text'),
          'Normal Text',
        );
      });

      test('Hacking/Adverse: Strips basic HTML tags', () {
        expect(
          SecurityAssertionService.sanitizeHtml('Hello <b>World</b>'),
          'Hello World',
        );
      });

      test('Hacking/Adverse: Strips script payloads', () {
        expect(
          SecurityAssertionService.sanitizeHtml(
            '<script>alert("XSS");</script>Hacked',
          ),
          'alert("XSS");Hacked',
        );
      });
    });
  });
}
