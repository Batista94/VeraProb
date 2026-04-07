import 'models/connectivity_state.dart';

/// Stateless signal-quality classifier based on ping age.
///
/// Pure functions only — no maps or mutable state owned here.
/// The FSM is: healthy → degraded → signalLost.
class ConnectivityAnalyzer {
  const ConnectivityAnalyzer();

  /// Classify [ConnectivityState] from [lastPing] age relative to [now].
  ///
  /// [degradedThreshold]  — age after which state becomes [ConnectivityState.degraded].
  /// [signalLostThreshold]— age after which state becomes [ConnectivityState.signalLost].
  ConnectivityState classify(
    DateTime lastPing,
    DateTime now, {
    required Duration degradedThreshold,
    required Duration signalLostThreshold,
  }) {
    final age = now.difference(lastPing);
    if (age <= degradedThreshold) return ConnectivityState.healthy;
    if (age <= signalLostThreshold) return ConnectivityState.degraded;
    return ConnectivityState.signalLost;
  }
}
