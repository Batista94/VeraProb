import 'package:flutter/services.dart';

/// [TextInputFormatter] that applies a BRL currency mask `R$ X.XXX,XX`.
///
/// Stores value as integer cents (INV-4). Use [toCents] / [fromCents]
/// to convert between masked display string and stored integer.
class BrlCurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final capped = digits.length > 13 ? digits.substring(0, 13) : digits;
    final cents = int.parse(capped);
    final formatted = fromCents(cents);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Converts a masked BRL string to integer cents. Returns null if unparseable.
  static int? toCents(String formatted) {
    final digits = formatted.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  /// Converts integer cents to masked BRL display string.
  static String fromCents(int cents) {
    final reais = cents ~/ 100;
    final centavos = cents % 100;
    final reaisFormatted = _formatReais(reais);
    return 'R\$ $reaisFormatted,${centavos.toString().padLeft(2, '0')}';
  }

  static String _formatReais(int reais) {
    final s = reais.toString();
    final buf = StringBuffer();
    var count = 0;
    for (var i = s.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(s[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }
}
