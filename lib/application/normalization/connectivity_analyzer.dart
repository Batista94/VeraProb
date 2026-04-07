import 'models/connectivity_state.dart';

/// Stateless signal-quality classifier based on ping age.
///
/// Pure functions only — no maps or mutable state owned here.
/// The FSM is: healthy → degraded → signalLost.
class ConnectivityAnalyzer {
  const ConnectivityAnalyzer();

  /// Classify [ConnectivityState] from [lastPing] age relative to [now].
  ///
  /// [degradedThreshold]      — age after which state becomes [ConnectivityState.degraded].
  /// [signalLostThreshold]    — age after which state becomes [ConnectivityState.signalLost].
  /// [previousLastRawPingAt]  — when provided, gap-recovery detection fires first:
  ///                            if the gap between [lastPing] and [previousLastRawPingAt]
  ///                            exceeds a threshold, the recovery ping itself is flagged.
  ///                            CRITICAL: the resulting state's lastRawPingAt MUST be set
  ///                            to [lastPing] so the next ping sees gap=0 (no recovery loop).
  ConnectivityState classify(
    DateTime lastPing,
    DateTime now, {
    DateTime? previousLastRawPingAt,
    required Duration degradedThreshold,
    required Duration signalLostThreshold,
  }) {
    // Gap-recovery detection: flag the first ping that arrives after a long silence.
    if (previousLastRawPingAt != null) {
      final gap = lastPing.difference(previousLastRawPingAt);
      if (gap > signalLostThreshold) return ConnectivityState.signalLost;
      if (gap > degradedThreshold) return ConnectivityState.degraded;
    }

    final age = now.difference(lastPing);
    if (age <= degradedThreshold) return ConnectivityState.healthy;
    if (age <= signalLostThreshold) return ConnectivityState.degraded;
    return ConnectivityState.signalLost;
  }
}
