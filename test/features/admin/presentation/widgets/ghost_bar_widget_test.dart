import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/features/admin/presentation/widgets/ghost_bar_widget.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('GhostBarWidget', () {
    testWidgets('renders DIFERENÇA OBSERVADA label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GhostBarWidget(
            deltaValue: 10.0,
            thresholdValue: 5.0,
            unit: 'km/h',
            clauseRef: 'VEL-001',
          ),
        ),
      );
      expect(find.text('DIFERENÇA OBSERVADA'), findsOneWidget);
    });

    testWidgets('renders LIMITE CONTRATUAL label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GhostBarWidget(
            deltaValue: 10.0,
            thresholdValue: 5.0,
            unit: 'km/h',
            clauseRef: 'VEL-001',
          ),
        ),
      );
      expect(find.text('LIMITE CONTRATUAL'), findsOneWidget);
    });

    testWidgets('displays delta value with unit', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GhostBarWidget(
            deltaValue: 10.0,
            thresholdValue: 5.0,
            unit: 'km/h',
            clauseRef: 'VEL-001',
          ),
        ),
      );
      expect(find.text('10.0 km/h'), findsOneWidget);
    });

    testWidgets('displays threshold value with unit', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GhostBarWidget(
            deltaValue: 10.0,
            thresholdValue: 5.0,
            unit: 'km/h',
            clauseRef: 'VEL-001',
          ),
        ),
      );
      expect(find.text('5.0 km/h'), findsOneWidget);
    });

    testWidgets('renders with ATR unit (min)', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GhostBarWidget(
            deltaValue: 8.5,
            thresholdValue: 15.0,
            unit: 'min',
            clauseRef: 'ATR-002',
          ),
        ),
      );
      expect(find.text('8.5 min'), findsOneWidget);
      expect(find.text('15.0 min'), findsOneWidget);
    });

    testWidgets(
      'zero-total guard: renders without crash when both values are 0',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const GhostBarWidget(
              deltaValue: 0.0,
              thresholdValue: 0.0,
              unit: 'km/h',
              clauseRef: 'VEL-001',
            ),
          ),
        );
        expect(find.text('DIFERENÇA OBSERVADA'), findsOneWidget);
        expect(find.text('0.0 km/h'), findsWidgets);
      },
    );

    testWidgets('zero threshold renders without crash', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GhostBarWidget(
            deltaValue: 5.0,
            thresholdValue: 0.0,
            unit: 'km/h',
            clauseRef: 'VEL-001',
          ),
        ),
      );
      expect(find.text('5.0 km/h'), findsOneWidget);
      expect(find.text('0.0 km/h'), findsOneWidget);
    });

    testWidgets('renders valores decimais corretamente', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const GhostBarWidget(
            deltaValue: 3.7,
            thresholdValue: 2.3,
            unit: 'eventos',
            clauseRef: 'ABR-001',
          ),
        ),
      );
      expect(find.text('3.7 eventos'), findsOneWidget);
      expect(find.text('2.3 eventos'), findsOneWidget);
    });
  });
}
