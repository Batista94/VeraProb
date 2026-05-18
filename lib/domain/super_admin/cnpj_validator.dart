/// Pure Módulo 11 structural validator for CNPJ (Brazilian tax identifier).
///
/// Guards API calls against CNPJs that are mathematically invalid before
/// they reach [ICnpjLookupService], preventing unnecessary round-trips (INV-7).
final class CnpjValidator {
  CnpjValidator._();

  // Receita Federal considers these sequences invalid even though some pass Módulo 11.
  static const _invalidSequences = {
    '00000000000000',
    '11111111111111',
    '22222222222222',
    '33333333333333',
    '44444444444444',
    '55555555555555',
    '66666666666666',
    '77777777777777',
    '88888888888888',
    '99999999999999',
  };

  static const _weights1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
  static const _weights2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];

  /// Returns true if [digits] is a structurally valid 14-digit CNPJ.
  ///
  /// Checks length, rejects repeated-digit sequences, then applies Módulo 11
  /// to both check digits. Does NOT verify registration status at Receita Federal.
  static bool isValid(String digits) {
    if (digits.length != 14) return false;
    if (_invalidSequences.contains(digits)) return false;

    // Parse ASCII digit codeUnits — avoids allocating a char list via split().
    final d = digits.codeUnits.map((c) => c - 0x30).toList(growable: false);
    if (d.any((c) => c < 0 || c > 9)) return false;

    return _checkDigit(d, _weights1, 12) && _checkDigit(d, _weights2, 13);
  }

  static bool _checkDigit(List<int> d, List<int> weights, int checkIndex) {
    var sum = 0;
    for (var i = 0; i < checkIndex; i++) {
      sum += d[i] * weights[i];
    }
    final remainder = sum % 11;
    final expected = remainder < 2 ? 0 : 11 - remainder;
    return d[checkIndex] == expected;
  }
}
