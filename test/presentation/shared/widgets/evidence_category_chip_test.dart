// Adversarial tests for EvidenceCategoryChip.
// Goal: prove that dirty/hostile input from Telegram never crashes the UI or PDF.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/shared/evidence_category_chip.dart';

void main() {
  // =========================================================================
  // labelFor — dirty input that WILL arrive from production
  // =========================================================================
  group('labelFor — adversarial input', () {
    test('empty string falls back to "— Sem tag"', () {
      expect(EvidenceCategoryChip.labelFor(''), '— Sem tag');
    });

    test('whitespace-only falls back to "— Sem tag"', () {
      expect(EvidenceCategoryChip.labelFor('   '), '— Sem tag');
    });

    test('UPPERCASE "INCIDENTE" is NOT matched (case-sensitive keys)', () {
      // Webhook stores lowercase. If DB has uppercase, it must NOT silently match.
      expect(EvidenceCategoryChip.labelFor('INCIDENTE'), '— Sem tag');
    });

    test('mixed case "Incidente" is NOT matched', () {
      expect(EvidenceCategoryChip.labelFor('Incidente'), '— Sem tag');
    });

    test('XSS-like string "<script>alert(1)</script>" falls back safely', () {
      expect(
        EvidenceCategoryChip.labelFor('<script>alert(1)</script>'),
        '— Sem tag',
      );
    });

    test('SQL injection attempt falls back safely', () {
      expect(EvidenceCategoryChip.labelFor("'; DROP TABLE --"), '— Sem tag');
    });

    test('unicode garbage falls back safely', () {
      expect(EvidenceCategoryChip.labelFor('🏴‍☠️💀'), '— Sem tag');
    });

    test('null-byte string falls back safely', () {
      expect(EvidenceCategoryChip.labelFor('\x00'), '— Sem tag');
    });

    test('very long string (1000 chars) falls back without crash', () {
      expect(EvidenceCategoryChip.labelFor('x' * 1000), '— Sem tag');
    });

    // Prove all 5 valid keys still work (regression guard)
    test('all 5 valid keys produce non-fallback labels', () {
      for (final key in ['incidente', 'oper', 'estado', 'doc', 'outros']) {
        final label = EvidenceCategoryChip.labelFor(key);
        expect(label, isNot('— Sem tag'), reason: 'key "$key" should match');
        expect(
          label.length,
          greaterThan(3),
          reason: 'key "$key" label too short',
        );
      }
    });
  });

  // =========================================================================
  // sortPriority — ordering invariants
  // =========================================================================
  group('sortPriority — ordering invariants', () {
    test(
      'incidente (0) < oper (1) < estado (2) < doc (3) < outros (4) < null (5)',
      () {
        final priorities = [
          'incidente',
          'oper',
          'estado',
          'doc',
          'outros',
          null,
        ].map(EvidenceCategoryChip.sortPriority).toList();
        // Must be strictly ascending
        for (var i = 0; i < priorities.length - 1; i++) {
          expect(
            priorities[i],
            lessThan(priorities[i + 1]),
            reason:
                'priority[$i]=${priorities[i]} must be < priority[${i + 1}]=${priorities[i + 1]}',
          );
        }
      },
    );

    test('unknown string gets same priority as null (5)', () {
      expect(EvidenceCategoryChip.sortPriority('garbage'), 5);
      expect(EvidenceCategoryChip.sortPriority(''), 5);
      expect(EvidenceCategoryChip.sortPriority('INCIDENTE'), 5);
    });

    test('sorting mixed list with unknowns puts them last with null', () {
      final items = ['incidente', 'garbage', null, 'doc', '', 'estado'];
      items.sort(
        (a, b) => EvidenceCategoryChip.sortPriority(
          a,
        ).compareTo(EvidenceCategoryChip.sortPriority(b)),
      );
      // incidente first, then estado, doc, then garbage/null/empty at end
      expect(items[0], 'incidente');
      expect(items[1], 'estado');
      expect(items[2], 'doc');
      // Last 3 are all priority 5 — order among them is stable but unspecified
      for (final item in items.sublist(3)) {
        expect(EvidenceCategoryChip.sortPriority(item), 5);
      }
    });
  });

  // =========================================================================
  // Widget — hostile rendering
  // =========================================================================
  group('Widget — hostile rendering', () {
    testWidgets('renders without crash for empty string category', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: EvidenceCategoryChip(category: '')),
        ),
      );
      expect(find.text('— Sem tag'), findsOneWidget);
    });

    testWidgets('renders without crash for XSS-like category', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EvidenceCategoryChip(category: '<img onerror=alert(1)>'),
          ),
        ),
      );
      // Should render fallback, not execute anything
      expect(find.text('— Sem tag'), findsOneWidget);
    });

    testWidgets('renders without crash for very long category string', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: EvidenceCategoryChip(category: 'a' * 500)),
        ),
      );
      expect(find.text('— Sem tag'), findsOneWidget);
    });
  });
}
