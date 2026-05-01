import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/mfa_disabled_banner.dart';

/// Wraps [child] in a [MaterialApp] with a [Scaffold] so the banner's
/// [Column] + [Expanded] layout has a bounded height.
Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('MfaDisabledBanner — visibility and background color (Task 5.3)', () {
    testWidgets(
      'banner is visible in debug/profile mode (kDebugMode is true in tests)',
      (tester) async {
        // In test builds kDebugMode == true, so the banner should appear.
        expect(MfaDisabledBanner.isVisibleInCurrentMode, isTrue);

        await tester.pumpWidget(
          _wrap(
            const MfaDisabledBanner(
              child: Center(child: Text('Child content')),
            ),
          ),
        );

        expect(
          find.text('⚠ MFA desabilitado (ambiente de desenvolvimento)'),
          findsOneWidget,
        );
        expect(find.text('Child content'), findsOneWidget);
      },
    );

    testWidgets('banner uses VeraProbColors.warning as background', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MfaDisabledBanner(child: Center(child: Text('Child content'))),
        ),
      );

      // The AnimatedContainer carries the BoxDecoration with the warning color.
      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = animatedContainer.decoration as BoxDecoration;
      expect(decoration.color, VeraProbColors.warning);
    });

    testWidgets('child widget is rendered below the banner', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MfaDisabledBanner(child: Center(child: Text('Child content'))),
        ),
      );

      // Both the banner text and the child should be present.
      expect(
        find.text('⚠ MFA desabilitado (ambiente de desenvolvimento)'),
        findsOneWidget,
      );
      expect(find.text('Child content'), findsOneWidget);

      // The banner text should be above the child content vertically.
      final bannerOffset = tester.getTopLeft(
        find.text('⚠ MFA desabilitado (ambiente de desenvolvimento)'),
      );
      final childOffset = tester.getTopLeft(find.text('Child content'));
      expect(bannerOffset.dy, lessThan(childOffset.dy));
    });

    testWidgets('banner text uses dark color for contrast on warning bg', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MfaDisabledBanner(child: Center(child: Text('Child content'))),
        ),
      );

      final text = tester.widget<Text>(
        find.text('⚠ MFA desabilitado (ambiente de desenvolvimento)'),
      );
      expect(text.style?.color, VeraProbColors.background);
    });

    testWidgets('banner spans full width', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MfaDisabledBanner(child: Center(child: Text('Child content'))),
        ),
      );

      // The AnimatedContainer should have width: double.infinity
      // which is enforced by the BoxConstraints from the Column.
      // We verify by checking the rendered size matches the screen width.
      final containerSize = tester.getSize(find.byType(AnimatedContainer));
      final screenSize = tester.getSize(find.byType(Scaffold));
      expect(containerSize.width, screenSize.width);
    });
  });

  group('MfaDisabledBanner — hover micro-interaction (Task 5.2)', () {
    testWidgets('initial elevation is 2dp (shadow offset)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MfaDisabledBanner(child: Center(child: Text('Child content'))),
        ),
      );

      final animatedContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = animatedContainer.decoration as BoxDecoration;
      final shadow = decoration.boxShadow!.first;
      expect(shadow.blurRadius, 2.0);
      expect(shadow.offset, const Offset(0, 2));
    });

    testWidgets('hover raises elevation to 4dp with AnimatedContainer 200ms', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const MfaDisabledBanner(child: Center(child: Text('Child content'))),
        ),
      );

      // Verify the AnimatedContainer has 200ms duration.
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(container.duration, const Duration(milliseconds: 200));

      // Simulate hover enter using a mouse gesture.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      // Move the pointer over the banner.
      await gesture.moveTo(tester.getCenter(find.byType(AnimatedContainer)));
      await tester.pump();

      // After hover, the shadow should reflect 4dp elevation.
      final hoveredContainer = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final hoveredDecoration = hoveredContainer.decoration as BoxDecoration;
      final hoveredShadow = hoveredDecoration.boxShadow!.first;
      expect(hoveredShadow.blurRadius, 4.0);
      expect(hoveredShadow.offset, const Offset(0, 4));
    });

    testWidgets('elevation returns to 2dp after hover exit', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MfaDisabledBanner(child: Center(child: Text('Child content'))),
        ),
      );

      // Simulate hover enter.
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      await gesture.moveTo(tester.getCenter(find.byType(AnimatedContainer)));
      await tester.pump();

      // Simulate hover exit — move pointer far away.
      await gesture.moveTo(const Offset(0, 500));
      await tester.pump();

      // Shadow should be back to 2dp.
      final container = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      final decoration = container.decoration as BoxDecoration;
      final shadow = decoration.boxShadow!.first;
      expect(shadow.blurRadius, 2.0);
      expect(shadow.offset, const Offset(0, 2));
    });

    testWidgets('uses MouseRegion for hover detection', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MfaDisabledBanner(child: Center(child: Text('Child content'))),
        ),
      );

      // The MfaDisabledBanner's MouseRegion wraps the AnimatedContainer.
      final mouseRegion = find.ancestor(
        of: find.byType(AnimatedContainer),
        matching: find.byType(MouseRegion),
      );
      expect(mouseRegion, findsOneWidget);
    });
  });
}
