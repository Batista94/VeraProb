import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
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
  // BPS Truncation Rules (Dízimas / Repeating Decimals)
  //
  // multiplyByBps uses integer truncation (`~/ 10000`), not rounding.
  // This is the canonical formula: (cents * bps) ~/ 10000.
  // Business intent: fractional cents are always dropped (floor), never rounded
  // up, so penalty multipliers never overshoot the contracted value.
  //
  // Rule: 10 000 BPS = 100% (1×). All rates are integers.
  // ---------------------------------------------------------------------------
  group('Money – BPS Truncation Rules (Dízimas)', () {
    // --- 1/3 = 3333.33... BPS ---
    test('3 333 BPS on R\$1,00 truncates to 33 cents, not 34', () {
      const money = Money(100); // R$1,00
      // Exact: 100 * 3333 / 10000 = 33.33 → truncated to 33
      expect(
        money.multiplyByBps(3333).cents,
        33,
        reason: 'Floor division: 33.33 becomes 33, not 34',
      );
    });

    // --- 2/3 = 6666.66... BPS ---
    test('6 667 BPS on R\$1,00 truncates to 66 cents — not 67 like rounding', () {
      const money = Money(100); // R$1,00
      // Exact: 100 * 6667 / 10000 = 66.67 → truncated to 66
      // operator * with 0.6667 would round to 67 — the two methods diverge here.
      expect(
        money.multiplyByBps(6667).cents,
        66,
        reason: 'Truncation: 66.67 → 66. operator* would round to 67',
      );
    });

    test(
      '1 BPS on R\$1,00 truncates to 0 cents (sub-cent penalty disappears)',
      () {
        const money = Money(100); // R$1,00
        // 100 * 1 / 10000 = 0.01 → truncated to 0
        expect(
          money.multiplyByBps(1).cents,
          0,
          reason: 'Sub-cent result must floor to 0, not round to 1',
        );
      },
    );

    test('9 999 BPS (99.99%) on R\$0,10 truncates to 9 cents, not 10', () {
      const money = Money(10); // R$0,10
      // 10 * 9999 / 10000 = 9.999 → truncated to 9
      // rounding would give 10 — truncation gives 9
      expect(
        money.multiplyByBps(9999).cents,
        9,
        reason: '9.999 truncates to 9 (floor), not 10 (round)',
      );
    });

    test('3 333 BPS on R\$1,50 truncates to 49 cents', () {
      const money = Money(150); // R$1,50
      // 150 * 3333 / 10000 = 49.995 → truncated to 49
      expect(
        money.multiplyByBps(3333).cents,
        49,
        reason: '49.995 truncates to 49 (floor)',
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

    // --- Behavioral contract: multiplyByBps vs operator* diverge on dízimas ---
    test(
      'multiplyByBps and operator* diverge on 2/3 — documents the contract',
      () {
        const money = Money(100);
        final viaOperator = money * 0.6667; // (100 * 0.6667).round() = 67
        final viaBps = money.multiplyByBps(6667); //  100 * 6667 ~/ 10000 = 66

        expect(viaOperator.cents, 67, reason: 'operator* rounds: 66.67 → 67');
        expect(viaBps.cents, 66, reason: 'multiplyByBps truncates: 66.67 → 66');
        expect(
          viaOperator,
          isNot(equals(viaBps)),
          reason:
              'The two methods are NOT interchangeable on repeating decimals',
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
