import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/presentation/shared/ui/ui.dart';

void main() {
  group('SparklineWidget', () {
    Future<void> pump(WidgetTester tester, List<int> values) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: SparklineWidget(values: values, color: Colors.green),
            ),
          ),
        ),
      );
    }

    testWidgets('empty series — renders without throw', (tester) async {
      await pump(tester, const []);
      expect(tester.takeException(), isNull);
      expect(find.byType(SparklineWidget), findsOneWidget);
    });

    testWidgets('single-point series — renders without throw', (tester) async {
      await pump(tester, const [50000]);
      expect(tester.takeException(), isNull);
      expect(find.byType(SparklineWidget), findsOneWidget);
    });

    testWidgets('flat series (all equal) — renders without throw', (
      tester,
    ) async {
      await pump(tester, const [30000, 30000, 30000, 30000]);
      expect(tester.takeException(), isNull);
      expect(find.byType(SparklineWidget), findsOneWidget);
    });

    testWidgets('normal series — widget tree contains CustomPaint', (
      tester,
    ) async {
      await pump(tester, const [10000, 20000, 15000, 25000, 18000]);
      expect(tester.takeException(), isNull);
      // At least one CustomPaint is ours (framework may add extras).
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
    });

    testWidgets('custom height is applied to inner SizedBox', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: SparklineWidget(
                values: [1000, 2000, 3000],
                color: Colors.red,
                height: 48,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.height == 48),
        findsAtLeastNWidgets(1),
      );
    });
  });
}
