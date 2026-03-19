import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';

void main() {
  group('SLAPenalties', () {
    const delayPenalty = Money(50);
    const downgradePenalty = Money(5000);
    const baseValue = Money(15000);

    test('should create with valid parameters (including gracePeriodMinutes)', () {
      final penalties = SLAPenalties.create(
        noShowPenaltyMultiplier: 1.5,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: delayPenalty,
        downgradePenaltyFlat: downgradePenalty,
        gracePeriodMinutes: 10,
        baseTripValue: baseValue,
      );

      expect(penalties.noShowPenaltyMultiplier, 1.5);
      expect(penalties.delayToleranceMinutes, 15);
      expect(penalties.gracePeriodMinutes, 10);
      expect(penalties.baseTripValue, baseValue);
    });

    test('should default gracePeriodMinutes to 0', () {
      final penalties = SLAPenalties.create(
        noShowPenaltyMultiplier: 1.5,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: delayPenalty,
        downgradePenaltyFlat: downgradePenalty,
      );

      expect(penalties.gracePeriodMinutes, 0);
    });

    test('should throw DomainException for negative gracePeriodMinutes', () {
      expect(
        () => SLAPenalties.create(
          noShowPenaltyMultiplier: 1.5,
          delayToleranceMinutes: 15,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
          gracePeriodMinutes: -1,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    group('serialization', () {
      test('round-trip serialization keeps gracePeriodMinutes', () {
        final original = SLAPenalties.create(
          noShowPenaltyMultiplier: 1.5,
          delayToleranceMinutes: 15,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
          gracePeriodMinutes: 20,
        );

        final json = original.toJson();
        final reconstituted = SLAPenalties.fromJson(json);

        expect(reconstituted, equals(original));
        expect(reconstituted.gracePeriodMinutes, 20);
      });

      test('fromJson should support missing gracePeriodMinutes (backward compat)', () {
        final json = {
          'noShowPenaltyMultiplier': 1.5,
          'delayToleranceMinutes': 15,
          'delayPenaltyPerMinuteCents': 50,
          'downgradePenaltyFlatCents': 5000,
          'noShowThresholdMinutes': 60,
          'earlyArrivalToleranceMinutes': 5,
          'dwellTimeMinutes': 3,
          'baseTripValueCents': 15000,
        };

        final penalties = SLAPenalties.fromJson(json);
        expect(penalties.gracePeriodMinutes, 0);
      });
    });
  });
}
