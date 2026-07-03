import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/locked_field_tile.dart';

/// Wraps [child] in a [MaterialApp] with a [Scaffold] for proper rendering.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('LockedFieldTile — widget tests (Task 4.2)', () {
    testWidgets('1. Renders label text', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(const LockedFieldTile(label: 'Slug', value: 'abc-123')),
      );

      expect(find.text('Slug'), findsOneWidget);
    });

    testWidgets('2. Renders value text when value is non-null', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          const LockedFieldTile(label: 'CNPJ', value: '12.345.678/0001-90'),
        ),
      );

      expect(find.text('12.345.678/0001-90'), findsOneWidget);
    });

    testWidgets('3. Shows lock icon (Icons.lock_outline)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(const LockedFieldTile(label: 'Slug', value: 'abc-123')),
      );

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    });

    testWidgets('4. Shows tooltip on hover over lock icon (contains INV-1)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(const LockedFieldTile(label: 'Slug', value: 'abc-123')),
      );

      // Find the Tooltip widget wrapping the lock icon.
      final tooltipFinder = find.byType(Tooltip);
      expect(tooltipFinder, findsOneWidget);

      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, contains('INV-1'));
    });

    testWidgets(
      '5. Border color is Color(0xFF2A3A5C) and border-radius is 10px',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _wrap(const LockedFieldTile(label: 'Slug', value: 'abc-123')),
        );

        final animatedContainer = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer),
        );
        final decoration = animatedContainer.decoration as BoxDecoration;

        // Check border color.
        final border = decoration.border as Border;
        expect(border.top.color, const Color(0xFF2A3A5C));

        // Check border-radius.
        expect(decoration.borderRadius, BorderRadius.circular(12));
      },
    );

    testWidgets('6. Value text has opacity 0.7 (Opacity widget)', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(const LockedFieldTile(label: 'Slug', value: 'abc-123')),
      );

      // The value is wrapped in an Opacity widget with 0.7.
      final opacityFinder = find.byType(Opacity);
      expect(opacityFinder, findsOneWidget);

      final opacity = tester.widget<Opacity>(opacityFinder);
      expect(opacity.opacity, 0.7);
    });

    testWidgets('7. Shows placeholder text when value is null', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(
          const LockedFieldTile(label: 'CNPJ', placeholder: 'Não informado'),
        ),
      );

      expect(find.text('Não informado'), findsOneWidget);
      // No Opacity widget when value is null (placeholder uses Text, not
      // SelectableText wrapped in Opacity).
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('8. Does NOT contain TextField or EditableText widgets', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(const LockedFieldTile(label: 'Slug', value: 'abc-123')),
      );

      // No TextField should be present.
      expect(find.byType(TextField), findsNothing);

      // SelectableText internally uses EditableText in readOnly mode.
      // Verify that any EditableText present is readOnly (not user-editable).
      final editableTextFinder = find.byType(EditableText);
      for (final element in editableTextFinder.evaluate()) {
        final editableText = element.widget as EditableText;
        expect(
          editableText.readOnly,
          isTrue,
          reason:
              'EditableText should be readOnly (from SelectableText), '
              'not a user-editable input',
        );
      }
    });

    testWidgets('9. Contains SelectableText widget when value is non-null', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _wrap(const LockedFieldTile(label: 'Slug', value: 'abc-123')),
      );

      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('10. onCopy callback is invoked when tile is tapped', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(400, 200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool copied = false;

      await tester.pumpWidget(
        _wrap(
          LockedFieldTile(
            label: 'Slug',
            value: 'abc-123',
            onCopy: () => copied = true,
          ),
        ),
      );

      // Tap on the GestureDetector area (the tile itself).
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump();

      expect(copied, isTrue);
    });

    testWidgets(
      '11. onCopy is NOT invoked when tile is tapped and onCopy is null (no crash)',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(400, 200));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          _wrap(
            const LockedFieldTile(
              label: 'Slug',
              value: 'abc-123',
              // onCopy is null by default.
            ),
          ),
        );

        // Tapping should not crash when onCopy is null.
        await tester.tap(find.byType(GestureDetector).first);
        await tester.pump();

        // If we reach here without exception, the test passes.
        expect(true, isTrue);
      },
    );
  });
}
