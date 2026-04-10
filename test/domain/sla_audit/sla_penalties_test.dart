import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';
import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/sla_penalties.dart';

// WASM boundary: 2^53 - 1 (max safe integer in JS double representation)
const _wasm53BitMax = 9007199254740991;

void main() {
  group('SLAPenalties', () {
    const delayPenalty = Money(50);
    const downgradePenalty = Money(5000);
    const baseValue = Money(15000);

    test(
      'should create with valid parameters (including gracePeriodMinutes)',
      () {
        final penalties = SLAPenalties.create(
          noShowPenaltyBps: 15000,
          delayToleranceMinutes: 15,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
          gracePeriodMinutes: 10,
          baseTripValue: baseValue,
        );

        expect(penalties.noShowPenaltyBps, 15000);
        expect(penalties.delayToleranceMinutes, 15);
        expect(penalties.gracePeriodMinutes, 10);
        expect(penalties.baseTripValue, baseValue);
      },
    );

    test('should default gracePeriodMinutes to 0', () {
      final penalties = SLAPenalties.create(
        noShowPenaltyBps: 15000,
        delayToleranceMinutes: 15,
        delayPenaltyPerMinute: delayPenalty,
        downgradePenaltyFlat: downgradePenalty,
      );

      expect(penalties.gracePeriodMinutes, 0);
    });

    test('should throw DomainException for negative gracePeriodMinutes', () {
      expect(
        () => SLAPenalties.create(
          noShowPenaltyBps: 15000,
          delayToleranceMinutes: 15,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
          gracePeriodMinutes: -1,
        ),
        throwsA(isA<DomainException>()),
      );
    });

    group('create() — all validation guards', () {
      test('throws DomainException when noShowPenaltyBps < 10000', () {
        expect(
          () => SLAPenalties.create(
            noShowPenaltyBps: 9999,
            delayToleranceMinutes: 0,
            delayPenaltyPerMinute: delayPenalty,
            downgradePenaltyFlat: downgradePenalty,
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when delayPenaltyPerMinute.cents <= 0', () {
        expect(
          () => SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 0,
            delayPenaltyPerMinute: const Money(0),
            downgradePenaltyFlat: downgradePenalty,
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when downgradePenaltyFlat.cents <= 0', () {
        expect(
          () => SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 0,
            delayPenaltyPerMinute: delayPenalty,
            downgradePenaltyFlat: const Money(0),
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when noShowThresholdMinutes < 0', () {
        expect(
          () => SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 0,
            delayPenaltyPerMinute: delayPenalty,
            downgradePenaltyFlat: downgradePenalty,
            noShowThresholdMinutes: -1,
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when earlyArrivalToleranceMinutes < 0', () {
        expect(
          () => SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 0,
            delayPenaltyPerMinute: delayPenalty,
            downgradePenaltyFlat: downgradePenalty,
            earlyArrivalToleranceMinutes: -1,
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when dwellTimeMinutes < 0', () {
        expect(
          () => SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 0,
            delayPenaltyPerMinute: delayPenalty,
            downgradePenaltyFlat: downgradePenalty,
            dwellTimeMinutes: -1,
          ),
          throwsA(isA<DomainException>()),
        );
      });

      test('throws DomainException when baseTripValue < 0', () {
        expect(
          () => SLAPenalties.create(
            noShowPenaltyBps: 10000,
            delayToleranceMinutes: 0,
            delayPenaltyPerMinute: delayPenalty,
            downgradePenaltyFlat: downgradePenalty,
            baseTripValue: const Money(-1),
          ),
          throwsA(isA<DomainException>()),
        );
      });
    });

    group('reconstitute — bypasses validation', () {
      test('reconstitute accepts noShowPenaltyBps below 10000', () {
        final p = SLAPenalties.reconstitute(
          noShowPenaltyBps: 5000,
          delayToleranceMinutes: 0,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
        );
        expect(p.noShowPenaltyBps, 5000);
      });
    });

    group('BPS escalation — progressive penalty ladder (INV-19)', () {
      // Formula: (baseCents * bps) ~/ 10000 — pure integer arithmetic, no drift
      const base = Money(10000); // R$ 100.00

      test('1.0x — base tier (10 000 BPS) returns original value', () {
        expect(base.multiplyByBps(10000), const Money(10000));
      });

      test('1.5x — recurrence tier (15 000 BPS) returns 1.5× value', () {
        expect(base.multiplyByBps(15000), const Money(15000));
      });

      test('2.0x — ceiling tier (20 000 BPS) returns double value', () {
        expect(base.multiplyByBps(20000), const Money(20000));
      });

      test('penalty calculated via noShowPenaltyBps field matches BPS formula', () {
        final penalties = SLAPenalties.create(
          noShowPenaltyBps: 15000,
          delayToleranceMinutes: 0,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
          baseTripValue: base,
        );
        final applied = penalties.baseTripValue.multiplyByBps(
          penalties.noShowPenaltyBps,
        );
        expect(applied, const Money(15000));
      });
    });

    group('BPS rounding — no IEEE-754 drift', () {
      test('19 999 BPS on Money(10 000) yields exact 19 999 via integer division', () {
        // (10000 * 19999) ~/ 10000 = 199990000 ~/ 10000 = 19999 — no float rounding
        expect(const Money(10000).multiplyByBps(19999), const Money(19999));
      });

      test('fromJson legacy multiplier 1.9999 round-trips to 19 999 BPS', () {
        final json = {
          'noShowPenaltyMultiplier': 1.9999,
          'delayToleranceMinutes': 5,
          'delayPenaltyPerMinuteCents': 50,
          'downgradePenaltyFlatCents': 5000,
        };
        final p = SLAPenalties.fromJson(json);
        // (1.9999 * 10000).round() — IEEE-754 rounds to 19999
        expect(p.noShowPenaltyBps, 19999);
      });

      test('fromJson legacy multiplier 1.5 yields exact 15 000 BPS', () {
        final json = {
          'noShowPenaltyMultiplier': 1.5,
          'delayToleranceMinutes': 5,
          'delayPenaltyPerMinuteCents': 50,
          'downgradePenaltyFlatCents': 5000,
        };
        final p = SLAPenalties.fromJson(json);
        expect(p.noShowPenaltyBps, 15000);
      });
    });

    group('WASM overflow guard — int64 / BPS ceiling', () {
      // _wasm53BitMax = 9007199254740991 (2^53-1) is the JS safe-integer limit.
      // Dart native ints are int64 (max = 9223372036854775807).
      // BPS formula: (cents * bps) ~/ 10000.
      // Multiplying _wasm53BitMax * 10000 overflows int64 — tests below document
      // the *safe* operational ceiling per BPS tier.

      test('Money stores 2^53-1 without precision loss (no arithmetic applied)', () {
        const stored = Money(_wasm53BitMax);
        expect(stored.cents, _wasm53BitMax);
      });

      test('SLAPenalties.create accepts baseTripValue at 2^53-1', () {
        final p = SLAPenalties.create(
          noShowPenaltyBps: 10000,
          delayToleranceMinutes: 0,
          delayPenaltyPerMinute: delayPenalty,
          downgradePenaltyFlat: downgradePenalty,
          baseTripValue: const Money(_wasm53BitMax),
        );
        expect(p.baseTripValue.cents, _wasm53BitMax);
      });

      test('1.0x BPS safe ceiling: int64.max ~/ 10000 = 922337203685477', () {
        // (922337203685477 * 10000) = 9223372036854770000 < int64.max — no overflow
        const safeCeiling1x = Money(922337203685477);
        expect(
          safeCeiling1x.multiplyByBps(10000),
          const Money(922337203685477),
        );
      });

      test('2.0x BPS safe ceiling: int64.max ~/ 20000 = 461168601842738', () {
        // (461168601842738 * 20000) = 9223372036854760000 < int64.max — no overflow
        // result: 9223372036854760000 ~/ 10000 = 922337203685476 = 2 × 461168601842738
        const safeCeiling2x = Money(461168601842738);
        expect(
          safeCeiling2x.multiplyByBps(20000),
          const Money(922337203685476),
        );
      });
    });

    group('serialization', () {
      test('round-trip serialization keeps gracePeriodMinutes', () {
        final original = SLAPenalties.create(
          noShowPenaltyBps: 15000,
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

      test(
        'fromJson should support missing gracePeriodMinutes (backward compat)',
        () {
          final json = {
            'noShowPenaltyBps': 15000,
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
        },
      );
    });
  });
}
