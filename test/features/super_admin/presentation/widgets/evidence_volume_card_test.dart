import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:veraprob/features/super_admin/presentation/widgets/evidence_volume_card.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  group('EvidenceVolumeCard', () {
    testWidgets('renders storage icon', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EvidenceVolumeCard(totalHistorical: 1000, totalMonthly: 50),
        ),
      );
      expect(find.byIcon(Icons.storage_outlined), findsOneWidget);
    });

    testWidgets('renders title label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EvidenceVolumeCard(totalHistorical: 1000, totalMonthly: 50),
        ),
      );
      expect(find.text('Volumetria de Evidências'), findsOneWidget);
    });

    testWidgets('formats totalHistorical with thousand separators', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EvidenceVolumeCard(totalHistorical: 15432, totalMonthly: 287),
        ),
      );
      // pt_BR uses dot as thousand separator
      expect(find.text('15.432'), findsOneWidget);
    });

    testWidgets('formats totalMonthly with "Este mês" label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const EvidenceVolumeCard(totalHistorical: 15432, totalMonthly: 287),
        ),
      );
      expect(find.text('Este mês: 287'), findsOneWidget);
    });

    testWidgets('formats large monthly value with thousand separators', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const EvidenceVolumeCard(totalHistorical: 100000, totalMonthly: 5000),
        ),
      );
      expect(find.text('100.000'), findsOneWidget);
      expect(find.text('Este mês: 5.000'), findsOneWidget);
    });

    testWidgets('renders zero values correctly', (tester) async {
      await tester.pumpWidget(
        _wrap(const EvidenceVolumeCard(totalHistorical: 0, totalMonthly: 0)),
      );
      expect(find.text('0'), findsOneWidget);
      expect(find.text('Este mês: 0'), findsOneWidget);
    });

    testWidgets('renders inside a Card with gradient decoration', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(const EvidenceVolumeCard(totalHistorical: 500, totalMonthly: 10)),
      );
      // Verify the Card widget exists
      expect(find.byType(Card), findsOneWidget);

      // Verify the gradient Container exists
      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(Card),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.gradient, isA<LinearGradient>());
    });

    testWidgets('is wrapped in SizedBox with width 240', (tester) async {
      await tester.pumpWidget(
        _wrap(const EvidenceVolumeCard(totalHistorical: 500, totalMonthly: 10)),
      );
      final sizedBox = tester.widget<SizedBox>(
        find.ancestor(of: find.byType(Card), matching: find.byType(SizedBox)),
      );
      expect(sizedBox.width, 240);
    });
  });
}
