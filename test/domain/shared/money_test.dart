import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/shared/money.dart';

void main() {
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
