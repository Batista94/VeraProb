/// CNPJ validation and formatting utilities.
///
/// Pure Dart — no Flutter imports (INV-18: Domain Sovereignty).
/// Implements Brazilian modulo-11 check-digit algorithm.
abstract final class CnpjValidator {
  /// Returns true when [cnpj] is a structurally valid Brazilian CNPJ.
  ///
  /// Strips formatting characters before validation. Rejects:
  /// - Inputs that don't yield exactly 14 digits after stripping
  /// - All-same-digit sequences (e.g. 11.111.111/1111-11)
  /// - Inputs failing the modulo-11 check-digit algorithm
  static bool isValid(String cnpj) {
    final digits = cnpj.replaceAll(RegExp(r'\D'), '');

    if (digits.length != 14) return false;

    // Reject all-same-digit sequences (structural fraud)
    if (RegExp(r'^(\d)\1{13}$').hasMatch(digits)) return false;

    final nums = digits.split('').map(int.parse).toList();

    // First check digit (position 12, index 12)
    const w1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    final sum1 = List.generate(12, (i) => nums[i] * w1[i]).fold(0, _add);
    final rem1 = sum1 % 11;
    final d1 = rem1 < 2 ? 0 : 11 - rem1;
    if (nums[12] != d1) return false;

    // Second check digit (position 13, index 13)
    const w2 = [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    final sum2 = List.generate(13, (i) => nums[i] * w2[i]).fold(0, _add);
    final rem2 = sum2 % 11;
    final d2 = rem2 < 2 ? 0 : 11 - rem2;
    return nums[13] == d2;
  }

  /// Formats a CNPJ string (with or without mask) as `00.000.000/0000-00`.
  ///
  /// Returns an empty string for empty input.
  /// Partial inputs are formatted up to the available digits.
  static String format(String cnpj) {
    final digits = cnpj.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';

    final buf = StringBuffer();
    for (var i = 0; i < digits.length && i < 14; i++) {
      if (i == 2 || i == 5) buf.write('.');
      if (i == 8) buf.write('/');
      if (i == 12) buf.write('-');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  static int _add(int a, int b) => a + b;
}
