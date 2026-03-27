import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/shift_pattern.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';
import 'package:veraprob/domain/sla_audit/vehicle_category.dart';
import 'package:veraprob/domain/sla_audit/week_cycle.dart';

void main() {
  setUpAll(() => tz_data.initializeTimeZones());

  final penalties = SLAPenalties.create(
    noShowPenaltyMultiplier: 1.5,
    delayToleranceMinutes: 15,
    delayPenaltyPerMinute: const Money(50),
    downgradePenaltyFlat: const Money(5000),
  );

  ShiftPattern makePattern({
    int index = 0,
    List<DayOfWeek>? days,
    String arrival = '08:00',
    String departure = '06:00',
    String timezone = 'America/Sao_Paulo',
  }) {
    return ShiftPattern.create(
      index: index,
      daysOfWeek: days ?? [DayOfWeek.monday, DayOfWeek.wednesday],
      arrivalTimeLocal: arrival,
      departureTimeLocal: departure,
      timezone: timezone,
      originZoneId: 'zone-origin',
      destinationZoneId: 'zone-dest',
      penalties: penalties,
    );
  }

  group('ShiftPattern.create — invariant validation', () {
    test('throws DomainException for negative index', () {
      expect(
        () => makePattern(index: -1),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for empty daysOfWeek', () {
      expect(
        () => makePattern(days: []),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for invalid time format (no colon)', () {
      expect(
        () => makePattern(arrival: '0800'),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for invalid hour value', () {
      expect(
        () => makePattern(arrival: '25:00'),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for invalid minute value', () {
      expect(
        () => makePattern(departure: '06:60'),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException for unknown timezone', () {
      expect(
        () => makePattern(timezone: 'NotReal/Timezone'),
        throwsA(isA<DomainException>()),
      );
    });

    test('throws DomainException when departure equals arrival', () {
      expect(
        () => makePattern(arrival: '07:00', departure: '07:00'),
        throwsA(isA<DomainException>()),
      );
    });
  });

  group('ShiftPattern.reconstitute', () {
    test('creates pattern without re-validating invariants', () {
      final pattern = ShiftPattern.reconstitute(
        index: 0,
        daysOfWeek: [DayOfWeek.friday],
        arrivalTimeLocal: '09:00',
        departureTimeLocal: '07:30',
        timezone: 'America/Sao_Paulo',
        originZoneId: 'zone-a',
        destinationZoneId: 'zone-b',
        penalties: penalties,
        requiredVehicleCategory: VehicleCategory.executive,
        weekCycle: WeekCycle.weekA,
      );

      expect(pattern.index, 0);
      expect(pattern.requiredVehicleCategory, VehicleCategory.executive);
      expect(pattern.weekCycle, WeekCycle.weekA);
    });
  });

  group('isOvernight', () {
    test('returns false when departure is before arrival', () {
      expect(makePattern(departure: '06:00', arrival: '08:00').isOvernight, isFalse);
    });

    test('returns true when departure is after arrival (overnight shift)', () {
      expect(makePattern(departure: '22:00', arrival: '06:00').isOvernight, isTrue);
    });
  });

  group('runsOn', () {
    test('returns true for a weekday in daysOfWeek', () {
      final pattern = makePattern(days: [DayOfWeek.monday, DayOfWeek.friday]);
      expect(pattern.runsOn(DateTime.monday), isTrue);
      expect(pattern.runsOn(DateTime.friday), isTrue);
    });

    test('returns false for a weekday not in daysOfWeek', () {
      final pattern = makePattern(days: [DayOfWeek.monday]);
      expect(pattern.runsOn(DateTime.tuesday), isFalse);
      expect(pattern.runsOn(DateTime.sunday), isFalse);
    });
  });

  group('toJson / fromJson round-trip', () {
    test('preserves all fields', () {
      final original = ShiftPattern.create(
        index: 2,
        daysOfWeek: [DayOfWeek.tuesday, DayOfWeek.thursday],
        arrivalTimeLocal: '10:00',
        departureTimeLocal: '08:30',
        timezone: 'America/Sao_Paulo',
        originZoneId: 'zone-a',
        destinationZoneId: 'zone-b',
        penalties: penalties,
        requiredVehicleCategory: VehicleCategory.conventional,
        weekCycle: WeekCycle.everyWeek,
      );

      final json = original.toJson();
      final restored = ShiftPattern.fromJson(json);

      expect(restored, equals(original));
    });
  });
}
