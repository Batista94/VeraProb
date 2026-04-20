import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
  // ---------------------------------------------------------------------------
  // FORENSIC AUDIT SUITE — INV-4 / INV-5 / INV-19
  //
  // Zero-tolerance proofs for:
  //   · IMMUTABILITY  — operator+, operator*, multiplyByBps never mutate source
  //   · MATH-BPS STRESS — 1.234.567,89 BRL × 17 BPS = 209.877 cents (exact)
  //   · HASHCODE      — Equatable contract: equal values → equal hashes
  //   · NO-DOUBLE     — All financial asserts use only int (cents)
  // ---------------------------------------------------------------------------
  group('FORENSIC: Immutability (INV-4)', () {
    test('IMMUT-01: operator+ returns new instance — source unchanged', () {
      const m1 = Money(1000);
      const m2 = Money(500);
      final result = m1 + m2;

      expect(result.cents, equals(1500));
      expect(
        identical(result, m1),
        isFalse,
        reason: 'operator+ MUST return a NEW instance',
      );
      expect(
        m1.cents,
        equals(1000),
        reason: 'source instance must remain immutable',
      );
    });

    test('IMMUT-02: operator* returns new instance — source unchanged', () {
      const m1 = Money(2000);
      final result = m1 * 1.5; // Bridge Conversion - Double Required
      expect(result.cents, equals(3000));
      expect(
        identical(result, m1),
        isFalse,
        reason: 'operator* MUST return a NEW instance',
      );
      expect(
        m1.cents,
        equals(2000),
        reason: 'source instance must remain immutable',
      );
    });

    test('IMMUT-03: multiplyByBps returns new instance — source unchanged', () {
      const m1 = Money(10000);
      final result = m1.multiplyByBps(10000);
      expect(result.cents, equals(10000));
      expect(
        identical(result, m1),
        isFalse,
        reason: 'multiplyByBps MUST return a NEW instance',
      );
      expect(
        m1.cents,
        equals(10000),
        reason: 'source instance must remain immutable',
      );
    });
  });

  group('FORENSIC: MATH-BPS Stress (INV-5 / INV-19)', () {
    test(
      'MATH-BPS: Multiplicação de 1.234.567,89 por 17 BPS = 209.877 cents',
      () {
        // R$ 1.234.567,89 = 123_456_789 centavos
        // Fórmula: (123_456_789 * 17 + 5000) ~/ 10000
        //        = (2_098_765_413 + 5000) ~/ 10000
        //        = 2_098_770_413 ~/ 10000
        //        = 209_877 cents  ← zero drift, pure BigInt integer math
        const amount = Money(123456789);
        final result = amount.multiplyByBps(17);

        // Assert uses only int — NO double
        expect(
          result.cents,
          equals(209877),
          reason:
              'MATH-BPS: R\$ 1.234.567,89 × 17 BPS must equal exactly '
              '209.877 cents with no floating-point drift',
        );
      },
    );
  });

  group('FORENSIC: Equality & hashCode contract (INV-7)', () {
    test('EQ-HC-01: hashCode consistent for equal values', () {
      const a = Money(100);
      const b = Money(100);
      expect(
        a.hashCode,
        equals(b.hashCode),
        reason: 'equal Money instances must produce equal hashCodes',
      );
    });

    test('EQ-HC-02: hashCode differs for distinct values', () {
      const a = Money(100);
      const b = Money(200);
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('EQ-HC-03: Money(0) equals Money(0) with consistent hashCode', () {
      const a = Money(0);
      const b = Money(0);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('FORENSIC: No-double asserts (INV-4)', () {
    test('ND-01: cents field is always int — never double', () {
      const m = Money(123456);
      expect(m.cents, isA<int>());
      expect(m.cents, isNot(isA<double>()));
    });

    test('ND-02: chained BPS operations yield exact int results', () {
      const base = Money(10000); // R$ 100,00
      final half = base.multiplyByBps(5000); // 50% → 5000 cents
      final full = half.multiplyByBps(20000); // 200% → 10000 cents
      // All asserts: int only
      expect(half.cents, equals(5000));
      expect(full.cents, equals(10000));
    });
  });

  // ---------------------------------------------------------------------------
  // IEEE-754 Precision Guard
  //
  // Validates that the VO entry point (fromDouble) absorbs IEEE-754 drift so
  // that integer arithmetic in the domain is always exact.
  // ---------------------------------------------------------------------------
  group('Money – IEEE-754 Precision Guard (Addition)', () {
    test('0.01 + 0.02 equals exactly 3 cents — no floating-point drift', () {
      // Raw IEEE-754: 0.01 + 0.02 == 0.030000000000000002 (NOT 0.03).
      // The VO converts to cents at the boundary, so domain arithmetic is pure int.
      final m1 = Money.fromDouble(0.01); // (0.01 * 100).round() = 1
      final m2 = Money.fromDouble(0.02); // (0.02 * 100).round() = 2

      final result = m1 + m2;

      expect(
        result.cents,
        3,
        reason: 'Cent-level addition must be exact: 1 + 2 = 3',
      );
      expect(result, const Money(3));
    });

    test('fromDouble boundary: 0.01 and 0.02 are stored as 1 and 2 cents', () {
      expect(Money.fromDouble(0.01).cents, 1);
      expect(Money.fromDouble(0.02).cents, 2);
    });

    test('repeated addition does not accumulate drift', () {
      // Adding Money.fromDouble(0.01) one hundred times must equal Money(100).
      var total = const Money(0);
      for (var i = 0; i < 100; i++) {
        total = total + Money.fromDouble(0.01);
      }
      expect(
        total.cents,
        100,
        reason: '100 × 1 cent = 100 cents, no drift allowed',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // BPS Rounding Rules (Half Away From Zero)
  //
  // multiplyByBps uses symmetric rounding (half away from zero):
  //   formula: (cents * bps + 5000) ~/ 10000  — with BigInt to prevent overflow
  //
  // This guarantees atomic, sealed ledger entries: each cent value is the
  // mathematically rounded result, not a floored approximation.
  //
  // Rule: 10 000 BPS = 100% (1×). All rates are integers.
  // ---------------------------------------------------------------------------
  group('Money – BPS Rounding Rules (Half Away From Zero)', () {
    // --- 1/3 = 3333.33... BPS ---
    test('3 333 BPS on R\$1,00 rounds down to 33 cents (0.33 < 0.5)', () {
      const money = Money(100); // R$1,00
      // Exact: 100 * 3333 / 10000 = 33.33 → rounds down to 33
      // (333300 + 5000) ~/ 10000 = 338300 ~/ 10000 = 33
      expect(
        money.multiplyByBps(3333).cents,
        33,
        reason: 'Round-down: 33.33 → 33 (fractional part 0.33 < 0.5)',
      );
    });

    // --- 2/3 = 6666.66... BPS ---
    test('6 667 BPS on R\$1,00 rounds up to 67 cents (0.67 ≥ 0.5)', () {
      const money = Money(100); // R$1,00
      // Exact: 100 * 6667 / 10000 = 66.67 → rounds up to 67
      // (666700 + 5000) ~/ 10000 = 671700 ~/ 10000 = 67
      expect(
        money.multiplyByBps(6667).cents,
        67,
        reason: 'Round-up: 66.67 → 67 (fractional part 0.67 ≥ 0.5)',
      );
    });

    test(
      '1 BPS on R\$1,00 rounds to 0 cents (sub-cent penalty disappears)',
      () {
        const money = Money(100); // R$1,00
        // 100 * 1 / 10000 = 0.01 → rounds down to 0 (0.01 < 0.5)
        // (100 + 5000) ~/ 10000 = 5100 ~/ 10000 = 0
        expect(
          money.multiplyByBps(1).cents,
          0,
          reason: 'Sub-cent result rounds down to 0: 0.01 < 0.5',
        );
      },
    );

    test(
      '9 999 BPS (99.99%) on R\$0,10 rounds up to 10 cents (0.999 ≥ 0.5)',
      () {
        const money = Money(10); // R$0,10
        // 10 * 9999 / 10000 = 9.999 → rounds up to 10
        // (99990 + 5000) ~/ 10000 = 104990 ~/ 10000 = 10
        expect(
          money.multiplyByBps(9999).cents,
          10,
          reason: '9.999 rounds up to 10 (fractional part 0.999 ≥ 0.5)',
        );
      },
    );

    test('3 333 BPS on R\$1,50 rounds up to 50 cents (0.995 ≥ 0.5)', () {
      const money = Money(150); // R$1,50
      // 150 * 3333 / 10000 = 49.995 → rounds up to 50
      // (499950 + 5000) ~/ 10000 = 504950 ~/ 10000 = 50
      expect(
        money.multiplyByBps(3333).cents,
        50,
        reason: '49.995 rounds up to 50 (fractional part 0.995 ≥ 0.5)',
      );
    });

    // --- Identity and boundaries ---
    test('10 000 BPS is identity (100%) — no change', () {
      const money = Money(137); // odd number to surface any off-by-one
      expect(money.multiplyByBps(10000).cents, 137);
    });

    test('0 BPS always produces Money(0)', () {
      const money = Money(999999);
      expect(money.multiplyByBps(0), const Money(0));
    });

    // --- Behavioral contract: multiplyByBps and operator* converge on dízimas ---
    test(
      'multiplyByBps and operator* converge on 2/3 under symmetric rounding',
      () {
        const money = Money(100);
        final viaOperator = money * 0.6667; // (100 * 0.6667).round() = 67
        final viaBps = money.multiplyByBps(6667); // (666700+5000)~/10000 = 67

        expect(viaOperator.cents, 67, reason: 'operator* rounds: 66.67 → 67');
        expect(viaBps.cents, 67, reason: 'multiplyByBps rounds: 66.67 → 67');
        expect(
          viaOperator,
          equals(viaBps),
          reason:
              'Both methods apply half-away-from-zero rounding — they converge',
        );
      },
    );
  });

  group('Money Value Object', () {
    test('creates from cents', () {
      const money = Money(1050);
      expect(money.cents, 1050);
    });

    test('creates from double using round()', () {
      final money = Money.fromDouble(10.50);
      expect(money.cents, 1050);

      // Testing precision handling
      final money2 = Money.fromDouble(10.555);
      expect(money2.cents, 1056); // 1055.5 rounds up
    });

    test('converts to double correctly', () {
      const money = Money(1050);
      expect(money.toDouble(), 10.50);
    });

    test('addition operator works correctly', () {
      const m1 = Money(1050);
      const m2 = Money(200);
      final result = m1 + m2;

      expect(result.cents, 1250);
      expect(result, const Money(1250)); // Tests equality too
    });

    test('multiplication operator works correctly with rounding', () {
      const money = Money(1000); // $10.00

      final result1 = money * 1.5;
      expect(result1.cents, 1500); // $15.00

      final result2 = money * 1.333;
      expect(result2.cents, 1333); // 1333.0 rounds to 1333
    });

    test('multiplyByBps handles basis points correctly', () {
      const money = Money(1000); // $10.00

      // 15000 BPS = 150% = 1.5x (10000 BPS = 100%)
      expect(money.multiplyByBps(15000), const Money(1500));

      // 3300 BPS = 33% = 0.33x ($3.30)
      expect(money.multiplyByBps(3300), const Money(330));
    });

    test('equality is based on cents value', () {
      const m1 = Money(1050);
      final m2 = Money.fromDouble(10.50);
      const m3 = Money(2000);

      expect(m1, equals(m2));
      expect(m1, isNot(equals(m3)));
    });
  });
}
