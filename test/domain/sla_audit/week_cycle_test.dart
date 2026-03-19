import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/sla_audit/week_cycle.dart';

void main() {
  group('WeekCycle', () {
    group('toJson / fromJson round-trip', () {
      test('all values serialize and deserialize correctly', () {
        for (final cycle in WeekCycle.values) {
          expect(WeekCycle.fromJson(cycle.toJson()), equals(cycle));
        }
      });

      test('null input defaults to everyWeek (backward compat)', () {
        expect(WeekCycle.fromJson(null), equals(WeekCycle.everyWeek));
      });

      test('unknown string defaults to everyWeek (backward compat)', () {
        expect(WeekCycle.fromJson('weekZ'), equals(WeekCycle.everyWeek));
      });
    });

    group('enum index for modular arithmetic', () {
      // weekCycle.index - 1 maps to week slot [0..3]
      test('everyWeek.index is 0', () => expect(WeekCycle.everyWeek.index, 0));
      test('weekA.index - 1 == 0', () => expect(WeekCycle.weekA.index - 1, 0));
      test('weekB.index - 1 == 1', () => expect(WeekCycle.weekB.index - 1, 1));
      test('weekC.index - 1 == 2', () => expect(WeekCycle.weekC.index - 1, 2));
      test('weekD.index - 1 == 3', () => expect(WeekCycle.weekD.index - 1, 3));
    });
  });
}
