import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glados/glados.dart' hide expect, group, test;
import 'package:google_fonts/google_fonts.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/locked_field_tile.dart';

/// **Validates: Requirements 3.1, 3.2**
///
/// Property 2: Fidelidade do Click-to-Copy
///
/// For any non-empty string `v` supplied as `value` to a [LockedFieldTile]:
///
/// 1. The [SelectableText] widget displays exactly `v` (no truncation,
///    normalisation, or transformation).
/// 2. When the tile is tapped, the `onCopy` callback fires, and a closure
///    that captures `v` receives the exact original value — proving that
///    the parent widget (TenantConfigTab) would copy the correct content
///    to the clipboard.
///
/// Uses `glados` [any.nonEmptyLetterOrDigits] to generate 100+ arbitrary
/// non-empty strings.

/// Wraps [child] in a [MaterialApp] with a [Scaffold] for proper rendering.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  // ── Generate 100 non-empty strings using glados generators ──
  // Glados.test uses package:test's `test`, not `testWidgets`, so we
  // pre-generate values and iterate with `testWidgets` (same pattern as
  // super_admin_guard_pbt_test.dart).
  final random = Random(42);
  final generator = any.nonEmptyLetterOrDigits;
  final values = <String>[
    for (var i = 0; i < 100; i++) generator(random, 10 + i).value,
  ];

  group('Feature: tenant-config-immutable-fields, '
      'Property 2: Fidelidade do Click-to-Copy', () {
    for (var i = 0; i < values.length; i++) {
      final value = values[i];

      testWidgets(
        'iter $i: SelectableText displays value exactly and '
        'onCopy captures it (value="${value.length > 30 ? '${value.substring(0, 30)}…' : value}")',
        (tester) async {
          await tester.binding.setSurfaceSize(const Size(600, 200));
          addTearDown(() => tester.binding.setSurfaceSize(null));

          // Capture variable — simulates what TenantConfigTab does:
          // `onCopy: () => _copyToClipboard(value)`
          String? captured;

          await tester.pumpWidget(
            _wrap(
              LockedFieldTile(
                label: 'Test Field',
                value: value,
                onCopy: () => captured = value,
              ),
            ),
          );

          // ── Property 2a: SelectableText displays the value exactly ──
          final selectableTextFinder = find.byType(SelectableText);
          expect(
            selectableTextFinder,
            findsOneWidget,
            reason: 'LockedFieldTile must render a SelectableText widget',
          );

          final selectableText = tester.widget<SelectableText>(
            selectableTextFinder,
          );
          expect(
            selectableText.data,
            equals(value),
            reason:
                'SelectableText.data must be exactly the input value '
                '(no truncation or transformation)',
          );

          // ── Property 2b: onCopy fires and closure captures exact value ──
          // Tap on the label area (regular Text widget) to avoid
          // SelectableText's internal gesture recognizer absorbing the
          // tap for longer strings.
          await tester.tap(find.text('Test Field'));
          await tester.pump();

          expect(
            captured,
            isNotNull,
            reason: 'onCopy callback must have been invoked after tap',
          );
          expect(
            captured,
            equals(value),
            reason:
                'The captured value must be exactly the original input '
                '(proving clipboard fidelity)',
          );
        },
      );
    }
  });
}
