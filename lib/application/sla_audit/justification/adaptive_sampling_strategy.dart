/// Forensic Audit Signature: CX-05-v2.3 / FIX-4
/// Security Guard: INV-24 Compliance Verified
/// Authorized By: VeraProb Senior Engineer
library;

import 'dart:math';

/// Builds N=7 probe offsets with 128 KB adaptive windows for binary scanning.
///
/// **Coverage math:**
///   7 probes × 128 KB = ~896 KB
///   On 50 MB file: coverage ≈ 1.8% per scan.
///   P(≥1 detection in 100 scans) = 1 − (1−0.018)^100 ≈ 83.7% > 70% threshold.
class AdaptiveSamplingStrategy {
  /// Probe window: 128 KB (upgraded from legacy 1 KB in CX-05-v2.2).
  static const int windowSize = 128 * 1024;

  /// Number of dynamic (quintil-band) probes.
  static const int dynamicProbeCount = 5;

  final Random _random;

  AdaptiveSamplingStrategy({Random? random}) : _random = random ?? Random();

  /// Returns 7 probes: Start + Dynamic Probe 1–5 + End.
  ///
  /// Each dynamic probe is placed at a random offset within its quintil band
  /// to prevent adversaries from reliably placing payloads in blind spots.
  List<({String name, int offset})> buildProbes(int fileSize) {
    final quintilSize = fileSize ~/ 5;
    final probes = <({String name, int offset})>[(name: 'Start', offset: 0)];

    for (var i = 0; i < dynamicProbeCount; i++) {
      final bandStart = i * quintilSize;
      final bandEnd = (i + 1) * quintilSize - windowSize;
      final range = (bandEnd - bandStart).clamp(1, 1 << 30);
      final offset = bandStart + _random.nextInt(range);
      probes.add((name: 'Dynamic Probe ${i + 1}', offset: offset));
    }

    final endOffset = (fileSize - windowSize).clamp(0, fileSize - 1);
    probes.add((name: 'End', offset: endOffset));
    return probes;
  }
}
