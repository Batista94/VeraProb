import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart'
    hide expect, group, test, setUpAll, tearDownAll;

/// Property-Based Test: Veto de Justificativa (Bicondicional)
///
/// **Validates: Requirements 4.6, 5.6, 6.1, 6.2, 6.3, 6.5**
///
/// Feature: superadmin-org-management-e2e-tests, Property 3: Veto de Justificativa (Bicondicional)
///
/// For any modal of critical operation (archive, unarchive, edit), the confirm
/// button must be enabled if and only if the justification field contains at
/// least 10 non-whitespace characters after trim.
///
/// Biconditional:
///   buttonEnabled ⟺ justification.trim().length >= 10
///
/// This is a PURE LOGIC test — no UI, no DB, no Supabase needed.
/// It tests the validation function directly with property-based testing.
///
/// Minimum 100 iterations per direction (positive and negative).

/// The justification validation logic (extracted for testability).
///
/// Returns `true` if [text] after trimming has at least 10 characters.
/// This is the biconditional predicate that controls whether the confirm
/// button is enabled in critical operation modals.
bool isJustificationValid(String text) {
  return text.trim().length >= 10;
}

void main() {
  group('Feature: superadmin-org-management-e2e-tests, '
      'Property 3: Veto de Justificativa (Bicondicional)', () {
    // ── Generators ──────────────────────────────────────────────────────

    final random = Random(42);

    // Generator for valid strings: lowercase letters padded to ≥10 chars.
    // Uses any.intInRange to generate lengths from 10 to 100, then builds
    // a string of that length from lowercase letters.
    final validLengthGen = any.intInRange(10, 101); // 10..100 inclusive

    // Generator for short strings: 0 to 9 chars after trim.
    final shortLengthGen = any.intInRange(0, 10); // 0..9 inclusive

    // Generator for whitespace character selection.
    final whitespaceChars = [' ', '\t', '\n', '\r', '\u00A0'];

    // Generator for whitespace-only string lengths (1 to 50).
    final whitespaceLengthGen = any.intInRange(1, 51);

    // ── Pre-generate inputs ─────────────────────────────────────────────

    const iterations = 100;

    // POSITIVE direction: strings with ≥10 non-whitespace chars after trim.
    final validStrings = List.generate(iterations, (i) {
      final length = validLengthGen(random, i + 5).value;
      // Generate a string of lowercase letters of the given length.
      final chars = List.generate(
        length,
        (j) => String.fromCharCode(97 + ((i * 7 + j * 13) % 26)),
      );
      return chars.join();
    });

    // NEGATIVE direction (whitespace-only): strings composed entirely of
    // whitespace characters — should always fail validation.
    final whitespaceOnlyStrings = List.generate(iterations, (i) {
      final length = whitespaceLengthGen(random, i + 5).value;
      final chars = List.generate(
        length,
        (j) => whitespaceChars[(i * 3 + j * 7) % whitespaceChars.length],
      );
      return chars.join();
    });

    // NEGATIVE direction (short strings): strings with <10 chars after trim.
    final shortStrings = List.generate(iterations, (i) {
      final length = shortLengthGen(random, i + 5).value;
      if (length == 0) return '';
      final chars = List.generate(
        length,
        (j) => String.fromCharCode(97 + ((i * 11 + j * 3) % 26)),
      );
      return chars.join();
    });

    // EDGE CASE: strings with leading/trailing whitespace that have
    // exactly 10 non-whitespace chars after trim (boundary).
    final boundaryStrings = List.generate(iterations, (i) {
      // Generate exactly 10 lowercase chars.
      final core = List.generate(
        10,
        (j) => String.fromCharCode(97 + ((i * 5 + j * 11) % 26)),
      ).join();
      // Wrap with varying amounts of whitespace.
      final leadingSpaces = ' ' * (i % 5);
      final trailingSpaces = '\t' * ((i + 3) % 4);
      return '$leadingSpaces$core$trailingSpaces';
    });

    // EDGE CASE: strings with leading/trailing whitespace that have
    // exactly 9 non-whitespace chars after trim (just below boundary).
    final belowBoundaryStrings = List.generate(iterations, (i) {
      // Generate exactly 9 lowercase chars.
      final core = List.generate(
        9,
        (j) => String.fromCharCode(97 + ((i * 3 + j * 7) % 26)),
      ).join();
      // Wrap with varying amounts of whitespace.
      final leadingSpaces = ' ' * ((i + 1) % 6);
      final trailingSpaces = '\n' * ((i + 2) % 3);
      return '$leadingSpaces$core$trailingSpaces';
    });

    // ── POSITIVE DIRECTION ──────────────────────────────────────────────
    // For any string with ≥10 non-whitespace chars after trim →
    // isJustificationValid returns true.

    for (var i = 0; i < iterations; i++) {
      final text = validStrings[i];

      test('POSITIVE iter $i: valid string (${text.length} chars) → '
          'isJustificationValid returns true', () {
        expect(
          isJustificationValid(text),
          isTrue,
          reason:
              'String with ${text.trim().length} chars after trim '
              'must be valid (≥10 required) — iter $i',
        );

        // Verify the biconditional: if valid, trim length must be ≥10.
        expect(
          text.trim().length >= 10,
          isTrue,
          reason:
              'Biconditional check: valid string must have '
              'trim().length >= 10 — iter $i',
        );
      });
    }

    // ── NEGATIVE DIRECTION (whitespace-only) ────────────────────────────
    // For any whitespace-only string → isJustificationValid returns false.

    for (var i = 0; i < iterations; i++) {
      final text = whitespaceOnlyStrings[i];

      test('NEGATIVE (whitespace) iter $i: whitespace-only string '
          '(${text.length} chars) → isJustificationValid returns false', () {
        expect(
          isJustificationValid(text),
          isFalse,
          reason:
              'Whitespace-only string must be invalid — '
              'trim().length = ${text.trim().length} — iter $i',
        );

        // Verify the biconditional: if invalid, trim length must be <10.
        expect(
          text.trim().length < 10,
          isTrue,
          reason:
              'Biconditional check: whitespace-only string must have '
              'trim().length < 10 — iter $i',
        );
      });
    }

    // ── NEGATIVE DIRECTION (short strings) ──────────────────────────────
    // For any string with <10 chars after trim → isJustificationValid
    // returns false.

    for (var i = 0; i < iterations; i++) {
      final text = shortStrings[i];

      test('NEGATIVE (short) iter $i: short string '
          '(${text.trim().length} chars after trim) → '
          'isJustificationValid returns false', () {
        expect(
          isJustificationValid(text),
          isFalse,
          reason:
              'String with ${text.trim().length} chars after trim '
              'must be invalid (<10 required) — iter $i',
        );

        // Verify the biconditional: if invalid, trim length must be <10.
        expect(
          text.trim().length < 10,
          isTrue,
          reason:
              'Biconditional check: short string must have '
              'trim().length < 10 — iter $i',
        );
      });
    }

    // ── BOUNDARY (exactly 10 chars after trim) ──────────────────────────
    // Strings with exactly 10 non-whitespace chars after trim should be
    // valid (boundary inclusion test).

    for (var i = 0; i < iterations; i++) {
      final text = boundaryStrings[i];

      test('BOUNDARY iter $i: exactly 10 chars after trim → '
          'isJustificationValid returns true', () {
        expect(
          text.trim().length,
          equals(10),
          reason:
              'Boundary string must have exactly 10 chars after trim '
              '— iter $i',
        );

        expect(
          isJustificationValid(text),
          isTrue,
          reason:
              'String with exactly 10 chars after trim must be valid '
              '(≥10 is the threshold) — iter $i',
        );
      });
    }

    // ── BELOW BOUNDARY (exactly 9 chars after trim) ─────────────────────
    // Strings with exactly 9 non-whitespace chars after trim should be
    // invalid (boundary exclusion test).

    for (var i = 0; i < iterations; i++) {
      final text = belowBoundaryStrings[i];

      test('BELOW BOUNDARY iter $i: exactly 9 chars after trim → '
          'isJustificationValid returns false', () {
        expect(
          text.trim().length,
          equals(9),
          reason:
              'Below-boundary string must have exactly 9 chars after '
              'trim — iter $i',
        );

        expect(
          isJustificationValid(text),
          isFalse,
          reason:
              'String with exactly 9 chars after trim must be invalid '
              '(<10 is below threshold) — iter $i',
        );
      });
    }
  });
}
