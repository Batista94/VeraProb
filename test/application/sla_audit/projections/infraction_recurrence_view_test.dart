import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/sla_audit/projections/infraction_recurrence_view.dart';

void main() {
  group('PriorInfractionDotView', () {
    test('can be constructed', () {
      final dot = PriorInfractionDotView(
        occurredAtUtc: DateTime.utc(2026, 3, 15),
        clauseRef: 'Cláusula 4.2',
      );
      expect(dot.clauseRef, 'Cláusula 4.2');
    });
  });

  group('InfractionRecurrenceView', () {
    test('firstOffense factory creates view with count=1 and empty priors', () {
      final view = InfractionRecurrenceView.firstOffense('ABC-1234');
      expect(view.vehiclePlate, 'ABC-1234');
      expect(view.infractionNumberThisMonth, 1);
      expect(view.priorInfractions, isEmpty);
    });

    test('infractionNumberThisMonth is int', () {
      final view = InfractionRecurrenceView.firstOffense('XYZ-5678');
      expect(view.infractionNumberThisMonth, isA<int>());
    });

    test('can hold multiple prior infractions', () {
      final view = InfractionRecurrenceView(
        vehiclePlate: 'DEF-9999',
        infractionNumberThisMonth: 3,
        priorInfractions: [
          PriorInfractionDotView(
            occurredAtUtc: DateTime.utc(2026, 3, 1),
            clauseRef: 'Cláusula 4.1',
          ),
          PriorInfractionDotView(
            occurredAtUtc: DateTime.utc(2026, 3, 10),
            clauseRef: 'Cláusula 4.2',
          ),
        ],
      );
      expect(view.priorInfractions.length, 2);
    });
  });
}
