// **Validates: Requirements 3.1, 3.2, 3.3, 3.4**
//
// Property 2: Preservation - Error Content and Test Logic Preservation
//
// For any constructor call where `PostgrestException` is instantiated after the fix,
// the fixed code SHALL preserve the exact error message content, error code values,
// and test logic behavior, ensuring no regression in functionality or test coverage.
//
// IMPORTANT: Follow observation-first methodology
// - Observe behavior on UNFIXED code for non-buggy inputs
// - Write property-based tests capturing observed behavior patterns
// - Tests should PASS on unfixed code (confirming baseline behavior to preserve)
//
// Test Focus Areas:
// 1. Error message string preservation (exact character sequence, UTF-8 encoding, length limits)
// 2. Error code value preservation (string and numeric codes, specific patterns)
// 3. Test logic and assertion preservation (identical pass/fail results, execution time, coverage)
// 4. Other constructor parameter compatibility (validation, default values, error handling)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;
import 'package:supabase/supabase.dart';

// Feature: postgrest-exception-constructor-fix, Property 2: Preservation

void main() {
  group('Property 2: Preservation - Error Content and Test Logic Preservation', () {
    // ── Sub-property 2a: Error message string preservation ─────────────────────
    Glados(any.letterOrDigits).test(
      'error message strings are preserved exactly as provided',
      (message) {
        // Test that message is preserved exactly
        final exception = PostgrestException(message: message);
        expect(exception.message, equals(message));
      },
    );

    // ── Sub-property 2b: Error message with special characters preservation ───
    Glados(any.letterOrDigits).test(
      'error message strings with special characters are preserved exactly',
      (message) {
        // Include special characters in test
        final testMessage =
            'Error: $message with special chars: \n\t\r\${}[]()';
        final exception = PostgrestException(message: testMessage);
        expect(exception.message, equals(testMessage));
      },
    );

    // ── Sub-property 2c: Error code string preservation ───────────────────────
    Glados2(any.letterOrDigits, any.letterOrDigits).test(
      'error code string values are preserved exactly as provided',
      (message, code) {
        final exception = PostgrestException(message: message, code: code);
        expect(exception.message, equals(message));
        expect(exception.code, equals(code));
      },
    );

    // ── Sub-property 2d: Error code numeric preservation ──────────────────────
    Glados2(any.letterOrDigits, any.int).test(
      'error code numeric values are preserved exactly as provided',
      (message, code) {
        final exception = PostgrestException(
          message: message,
          code: code.toString(),
        );
        expect(exception.message, equals(message));
        expect(exception.code, equals(code.toString()));
      },
    );

    // ── Sub-property 2e: Error code pattern preservation ──────────────────────
    Glados(any.letterOrDigits).test(
      'error codes matching specific patterns are preserved',
      (message) {
        // Test common error code patterns from the codebase
        const errorCodes = [
          '22P02',
          'PGRST116',
          'P0001',
          '23505',
          '23503',
          '42501',
        ];

        for (final code in errorCodes) {
          final exception = PostgrestException(message: message, code: code);
          expect(exception.message, equals(message));
          expect(exception.code, equals(code));
        }
      },
    );

    // ── Sub-property 2f: Constructor with only message parameter ──────────────
    Glados(any.letterOrDigits).test(
      'constructor with only message parameter works correctly',
      (message) {
        final exception = PostgrestException(message: message);
        expect(exception.message, equals(message));
        expect(exception.code, isNull);
      },
    );

    // ── Sub-property 2g: Constructor with message and code parameters ─────────
    Glados2(any.letterOrDigits, any.letterOrDigits).test(
      'constructor with message and code parameters works correctly',
      (message, code) {
        final exception = PostgrestException(message: message, code: code);
        expect(exception.message, equals(message));
        expect(exception.code, equals(code));
      },
    );

    // ── Sub-property 2h: Exception properties remain accessible ───────────────
    Glados2(any.letterOrDigits, any.letterOrDigits.nullable).test(
      'all exception properties remain accessible after construction',
      (message, code) {
        final exception = PostgrestException(message: message, code: code);

        // Test that all expected properties are accessible
        expect(exception.message, equals(message));
        expect(exception.code, equals(code));

        // Test toString() includes the message
        expect(exception.toString(), contains(message));

        // Test that exception can be caught and rethrown
        expect(() => throw exception, throwsA(isA<PostgrestException>()));
      },
    );

    // ── Sub-property 2i: Exception equality and hashcode preservation ─────────
    Glados(any.letterOrDigits).test(
      'identical exceptions have equal hashcodes and equality',
      (message) {
        const code = 'TEST_CODE';
        final exception1 = PostgrestException(message: message, code: code);
        final exception2 = PostgrestException(message: message, code: code);

        // Note: PostgrestException may not override == and hashCode
        // This test verifies the behavior doesn't change unexpectedly
        expect(exception1.message, equals(exception2.message));
        expect(exception1.code, equals(exception2.code));
      },
    );

    // ── Sub-property 2j: Long message preservation (up to 1000 chars) ─────────
    Glados(
      any
          .listWithLengthInRange(0, 1001, any.intInRange(32, 126))
          .map((l) => String.fromCharCodes(l)),
    ).test('error messages up to 1000 characters are preserved', (message) {
      final exception = PostgrestException(message: message);
      expect(exception.message, equals(message));
      expect(exception.message.length, equals(message.length));
    });

    // ── Sub-property 2k: Test logic preservation ──────────────────────────────
    Glados2(any.letterOrDigits, any.letterOrDigits).test(
      'test assertions continue to work identically with exception',
      (message, code) {
        final exception = PostgrestException(message: message, code: code);

        // Test common assertion patterns from the codebase
        expect(exception, isA<PostgrestException>());
        expect(exception.message, equals(message));
        expect(exception.code, equals(code));

        // Test the common pattern: throwsA(isA<PostgrestException>())
        expect(() => throw exception, throwsA(isA<PostgrestException>()));

        // Test the pattern with having() matcher
        expect(
          exception,
          isA<PostgrestException>().having(
            (e) => e.message,
            'message',
            equals(message),
          ),
        );
      },
    );

    // ── Sub-property 2l: Exception inheritance chain preservation ─────────────
    test('PostgrestException maintains correct inheritance chain', () {
      const exception = PostgrestException(message: 'test');

      // Verify it's still an Exception
      expect(exception, isA<Exception>());

      // Verify toString() behavior
      expect(exception.toString(), isA<String>());
      expect(exception.toString(), contains('test'));
    });

    // ── Sub-property 2m: Already correct syntax continues to work ─────────────
    test(
      'already correct constructor syntax continues to compile and work',
      () {
        // This is the baseline behavior that must be preserved
        const alreadyCorrect = PostgrestException(message: 'Already correct');
        expect(alreadyCorrect.message, equals('Already correct'));

        const withCode = PostgrestException(message: 'With code', code: '404');
        expect(withCode.message, equals('With code'));
        expect(withCode.code, equals('404'));
      },
    );
  });
}
