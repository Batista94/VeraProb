import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/infraction_recurrence_report.dart';

void main() {
  group('PriorInfractionDot', () {
    test('equality based on occurredAtUtc and clauseRef', () {
      final t = DateTime.utc(2026, 4, 1, 8, 0);
      final a = PriorInfractionDot(occurredAtUtc: t, clauseRef: 'VEL-001');
      final b = PriorInfractionDot(occurredAtUtc: t, clauseRef: 'VEL-001');
      expect(a, b);
    });

    test('inequality when clauseRef differs', () {
      final t = DateTime.utc(2026, 4, 1, 8, 0);
      final a = PriorInfractionDot(occurredAtUtc: t, clauseRef: 'VEL-001');
      final b = PriorInfractionDot(occurredAtUtc: t, clauseRef: 'ATR-002');
      expect(a, isNot(b));
    });
  });

  group('InfractionRecurrenceReport', () {
    final dot1 = PriorInfractionDot(
      occurredAtUtc: DateTime.utc(2026, 4, 2, 9, 0),
      clauseRef: 'VEL-001',
    );
    final dot2 = PriorInfractionDot(
      occurredAtUtc: DateTime.utc(2026, 4, 5, 14, 0),
      clauseRef: 'ATR-002',
    );

    test('firstOffense constructor produces count=1 and empty priors', () {
      const report = InfractionRecurrenceReport.firstOffense('ABC-1234');
      expect(report.vehiclePlate, 'ABC-1234');
      expect(report.infractionNumberThisMonth, 1);
      expect(report.priorInfractions, isEmpty);
    });

    test('full constructor carries priorInfractions in order', () {
      final report = InfractionRecurrenceReport(
        vehiclePlate: 'XYZ-9999',
        infractionNumberThisMonth: 3,
        priorInfractions: [dot1, dot2],
      );
      expect(report.infractionNumberThisMonth, 3);
      expect(report.priorInfractions.length, 2);
      expect(report.priorInfractions.first, dot1);
      expect(report.priorInfractions.last, dot2);
    });

    test('equality considers all fields', () {
      final r1 = InfractionRecurrenceReport(
        vehiclePlate: 'ABC-1234',
        infractionNumberThisMonth: 2,
        priorInfractions: [dot1],
      );
      final r2 = InfractionRecurrenceReport(
        vehiclePlate: 'ABC-1234',
        infractionNumberThisMonth: 2,
        priorInfractions: [dot1],
      );
      expect(r1, r2);
    });

    test('inequality when infractionNumber differs', () {
      const r1 = InfractionRecurrenceReport(
        vehiclePlate: 'ABC-1234',
        infractionNumberThisMonth: 1,
        priorInfractions: [],
      );
      final r2 = InfractionRecurrenceReport(
        vehiclePlate: 'ABC-1234',
        infractionNumberThisMonth: 2,
        priorInfractions: [dot1],
      );
      expect(r1, isNot(r2));
    });
  });
}
