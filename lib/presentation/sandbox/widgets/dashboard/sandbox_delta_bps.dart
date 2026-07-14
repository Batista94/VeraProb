/// INV-5: basis-point delta with symmetric (half-up) integer rounding.
///
/// Matches ledger convention: positive bps = simulated fines **lower** than
/// baseline (projected savings). Formula uses BIGINT-safe [BigInt] math.
abstract final class SandboxDeltaBps {
  /// Returns `((baseline - simulated) * 10000)` / [baselineCents] with
  /// symmetric rounding, or `null` when baseline is zero.
  static int? compute({
    required int baselineCents,
    required int simulatedCents,
  }) {
    if (baselineCents <= 0) return null;

    final diff = baselineCents - simulatedCents;
    final numer = BigInt.from(diff) * BigInt.from(10000);
    final den = BigInt.from(baselineCents);
    final half = den ~/ BigInt.from(2);
    final biased = diff >= 0 ? numer + half : numer - half;
    return (biased ~/ den).toInt();
  }

  /// Formats e.g. `1500` → `1.500` (BR thousands separator, integer bps).
  static String format(int bps) {
    final abs = bps.abs();
    final s = abs.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return bps < 0 ? '-${buf.toString()}' : buf.toString();
  }
}
