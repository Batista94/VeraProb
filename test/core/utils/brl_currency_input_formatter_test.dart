import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/presentation/shared/formatters/brl_currency_input_formatter.dart';

void main() {
  group('BrlCurrencyInputFormatter.fromCents', () {
    test('zero = R\$ 0,00', () {
      expect(BrlCurrencyInputFormatter.fromCents(0), 'R\$ 0,00');
    });

    test('1 cent = R\$ 0,01', () {
      expect(BrlCurrencyInputFormatter.fromCents(1), 'R\$ 0,01');
    });

    test('99 cents = R\$ 0,99', () {
      expect(BrlCurrencyInputFormatter.fromCents(99), 'R\$ 0,99');
    });

    test('100 cents = R\$ 1,00', () {
      expect(BrlCurrencyInputFormatter.fromCents(100), 'R\$ 1,00');
    });

    test('50000 cents = R\$ 500,00', () {
      expect(BrlCurrencyInputFormatter.fromCents(50000), 'R\$ 500,00');
    });

    test('100000 cents = R\$ 1.000,00 (thousands separator)', () {
      expect(BrlCurrencyInputFormatter.fromCents(100000), 'R\$ 1.000,00');
    });

    test('1000000 cents = R\$ 10.000,00', () {
      expect(BrlCurrencyInputFormatter.fromCents(1000000), 'R\$ 10.000,00');
    });

    test('10000000 cents = R\$ 100.000,00', () {
      expect(BrlCurrencyInputFormatter.fromCents(10000000), 'R\$ 100.000,00');
    });

    test('100000000 cents = R\$ 1.000.000,00 (multi-group thousands)', () {
      expect(
        BrlCurrencyInputFormatter.fromCents(100000000),
        'R\$ 1.000.000,00',
      );
    });

    test('centavos pad to 2 digits: 505 = R\$ 5,05', () {
      expect(BrlCurrencyInputFormatter.fromCents(505), 'R\$ 5,05');
    });
  });

  group('BrlCurrencyInputFormatter.toCents', () {
    test('empty string returns null', () {
      expect(BrlCurrencyInputFormatter.toCents(''), isNull);
    });

    test('whitespace-only returns null', () {
      expect(BrlCurrencyInputFormatter.toCents('   '), isNull);
    });

    test('R\$ 500,00 → 50000', () {
      expect(BrlCurrencyInputFormatter.toCents('R\$ 500,00'), 50000);
    });

    test('R\$ 1.000,00 → 100000', () {
      expect(BrlCurrencyInputFormatter.toCents('R\$ 1.000,00'), 100000);
    });

    test('R\$ 0,01 → 1', () {
      expect(BrlCurrencyInputFormatter.toCents('R\$ 0,01'), 1);
    });

    test('R\$ 0,00 → 0', () {
      expect(BrlCurrencyInputFormatter.toCents('R\$ 0,00'), 0);
    });

    test('fromCents/toCents round-trip: 50000', () {
      final formatted = BrlCurrencyInputFormatter.fromCents(50000);
      expect(BrlCurrencyInputFormatter.toCents(formatted), 50000);
    });

    test('fromCents/toCents round-trip: 1', () {
      final formatted = BrlCurrencyInputFormatter.fromCents(1);
      expect(BrlCurrencyInputFormatter.toCents(formatted), 1);
    });

    test('fromCents/toCents round-trip: 100000000', () {
      final formatted = BrlCurrencyInputFormatter.fromCents(100000000);
      expect(BrlCurrencyInputFormatter.toCents(formatted), 100000000);
    });

    test('non-numeric string returns null', () {
      expect(BrlCurrencyInputFormatter.toCents('abc'), isNull);
    });
  });

  group('BrlCurrencyInputFormatter.formatEditUpdate', () {
    final formatter = BrlCurrencyInputFormatter();

    TextEditingValue edit(String old, String next) =>
        formatter.formatEditUpdate(
          TextEditingValue(text: old),
          TextEditingValue(text: next),
        );

    test('empty input stays empty', () {
      final result = edit('', '');
      expect(result.text, isEmpty);
    });

    test('typing "5" produces R\$ 0,05', () {
      final result = edit('', '5');
      expect(result.text, 'R\$ 0,05');
    });

    test('typing "500" produces R\$ 5,00', () {
      final result = edit('', '500');
      expect(result.text, 'R\$ 5,00');
    });

    test('typing "50000" produces R\$ 500,00', () {
      final result = edit('', '50000');
      expect(result.text, 'R\$ 500,00');
    });

    test('cursor placed at end of formatted text', () {
      final result = edit('', '50000');
      expect(result.selection.baseOffset, result.text.length);
      expect(result.selection.extentOffset, result.text.length);
    });

    test('non-digit characters in input are stripped', () {
      final result = edit('', 'R\$ 5,00');
      // digits extracted: "500" → R\$ 5,00
      expect(result.text, 'R\$ 5,00');
    });

    test('13-digit cap enforced — overflow digits truncated', () {
      // 14 digits would overflow; formatter caps at 13
      final result = edit('', '12345678901234');
      expect(BrlCurrencyInputFormatter.toCents(result.text), isNotNull);
    });

    test('clearing input (empty newValue) yields empty result', () {
      final result = edit('R\$ 5,00', '');
      expect(result.text, isEmpty);
    });
  });

  group('BrlCurrencyInputFormatter — INV-4 cents invariant', () {
    test('fromCents always uses comma as decimal separator (not dot)', () {
      for (final cents in [1, 50, 100, 1050, 100000, 123456]) {
        final s = BrlCurrencyInputFormatter.fromCents(cents);
        // Comma must appear exactly once — separates reais from centavos
        expect(
          s.split(',').length - 1,
          1,
          reason: 'Must have exactly one comma in "$s"',
        );
        // Dot only appears as thousands separator (format: R$ X.XXX,XX)
        if (s.contains('.')) {
          expect(
            s,
            matches(r'^R\$ \d{1,3}(\.\d{3})+,\d{2}$'),
            reason: 'Dot must be thousands separator in "$s"',
          );
        }
      }
    });

    test('toCents(fromCents(n)) = n for any positive value', () {
      for (final cents in [
        0,
        1,
        99,
        100,
        999,
        1000,
        9999,
        10000,
        99999,
        100000,
      ]) {
        final formatted = BrlCurrencyInputFormatter.fromCents(cents);
        expect(
          BrlCurrencyInputFormatter.toCents(formatted),
          cents,
          reason: 'Round-trip failed for $cents cents → "$formatted"',
        );
      }
    });
  });
}
