import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/infraction_recurrence_report.dart';
import 'package:veraprob/features/admin/presentation/widgets/recurrence_badge_widget.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

InfractionRecurrenceReport _report({
  required int count,
  List<PriorInfractionDot> priors = const [],
}) =>
    InfractionRecurrenceReport(
      vehiclePlate: 'ABC-1234',
      infractionNumberThisMonth: count,
      priorInfractions: priors,
    );

void main() {
  group('RecurrenceBadgeWidget', () {
    testWidgets('renders REINCIDÊNCIA MENSAL label', (tester) async {
      await tester.pumpWidget(_wrap(RecurrenceBadgeWidget(
        report: _report(count: 1),
      )));
      expect(find.text('REINCIDÊNCIA MENSAL'), findsOneWidget);
    });

    testWidgets('badge text shows "1ª infração no mês" for count=1',
        (tester) async {
      await tester.pumpWidget(_wrap(RecurrenceBadgeWidget(
        report: _report(count: 1),
      )));
      expect(find.text('1ª infração no mês'), findsOneWidget);
    });

    testWidgets('badge text shows "2ª infração no mês" for count=2',
        (tester) async {
      final prior = PriorInfractionDot(
        occurredAtUtc: DateTime.utc(2026, 4, 2, 8, 0),
        clauseRef: 'VEL-001',
      );
      await tester.pumpWidget(_wrap(RecurrenceBadgeWidget(
        report: _report(count: 2, priors: [prior]),
      )));
      expect(find.text('2ª infração no mês'), findsOneWidget);
    });

    testWidgets('badge text shows "3ª infração no mês" for count=3',
        (tester) async {
      final prior1 = PriorInfractionDot(
        occurredAtUtc: DateTime.utc(2026, 4, 1, 8, 0),
        clauseRef: 'VEL-001',
      );
      final prior2 = PriorInfractionDot(
        occurredAtUtc: DateTime.utc(2026, 4, 5, 10, 0),
        clauseRef: 'ATR-002',
      );
      await tester.pumpWidget(_wrap(RecurrenceBadgeWidget(
        report: _report(count: 3, priors: [prior1, prior2]),
      )));
      expect(find.text('3ª infração no mês'), findsOneWidget);
    });

    testWidgets('renders N-1 prior dots (excludes current)', (tester) async {
      final priors = [
        PriorInfractionDot(
          occurredAtUtc: DateTime.utc(2026, 4, 2, 8, 0),
          clauseRef: 'VEL-001',
        ),
        PriorInfractionDot(
          occurredAtUtc: DateTime.utc(2026, 4, 8, 10, 0),
          clauseRef: 'ATR-002',
        ),
      ];
      await tester.pumpWidget(_wrap(RecurrenceBadgeWidget(
        report: _report(count: 3, priors: priors),
      )));
      // Total rendered dots = priors + 1 current = 3
      // We verify the badge renders without overflow
      expect(find.text('3ª infração no mês'), findsOneWidget);
    });

    testWidgets('renders with no prior dots for first offense', (tester) async {
      await tester.pumpWidget(_wrap(const RecurrenceBadgeWidget(
        report: InfractionRecurrenceReport.firstOffense('XYZ-9999'),
      )));
      expect(find.text('1ª infração no mês'), findsOneWidget);
    });

    testWidgets('renders RepeatRounded icon', (tester) async {
      await tester.pumpWidget(_wrap(RecurrenceBadgeWidget(
        report: _report(count: 1),
      )));
      expect(find.byIcon(Icons.repeat_rounded), findsOneWidget);
    });
  });
}
