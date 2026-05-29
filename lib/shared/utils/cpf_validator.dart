/// CPF validation utilities.
///
/// Pure Dart — no Flutter imports (INV-18: Domain Sovereignty).
/// Implements Brazilian modulo-11 check-digit algorithm.
abstract final class CpfValidator {
  /// Returns true when [cpf] is a structurally valid Brazilian CPF.
  ///
  /// Strips formatting characters before validation. Rejects:
  /// - Inputs that don't yield exactly 11 digits after stripping
  /// - All-same-digit sequences (e.g. 111.111.111-11)
  /// - Inputs failing the modulo-11 check-digit algorithm
  static bool isValid(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');

    if (digits.length != 11) return false;

    // Reject all-same-digit sequences (structural fraud)
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

    final nums = digits.split('').map(int.parse).toList();

    // First check digit (position 9, index 9)
    const w1 = [10, 9, 8, 7, 6, 5, 4, 3, 2];
    final sum1 = List.generate(9, (i) => nums[i] * w1[i]).fold(0, _add);
    final rem1 = sum1 % 11;
    final d1 = rem1 < 2 ? 0 : 11 - rem1;
    if (nums[9] != d1) return false;

    // Second check digit (position 10, index 10)
    const w2 = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2];
    final sum2 = List.generate(10, (i) => nums[i] * w2[i]).fold(0, _add);
    final rem2 = sum2 % 11;
    final d2 = rem2 < 2 ? 0 : 11 - rem2;
    return nums[10] == d2;
  }

  static int _add(int a, int b) => a + b;
}
