/// INV-12: Late-Arrival Window Policy
///
/// Enforces the 48-hour reprocessing window for late-arriving telemetry facts.
/// A `noShow` verdict can only be overturned if the fact arrives within 48 hours
/// of [windowEndUtc]. After that, the verdict is final and immutable.
///
/// This is a pure-Dart policy class (INV-18: Domain Sovereignty).
/// Zero external dependencies — safe to instantiate anywhere in the domain.
class LateArrivalWindowPolicy {
  const LateArrivalWindowPolicy();

  /// The default reprocessing window per INV-12.
  static const Duration defaultWindow = Duration(hours: 48);

  /// Returns `true` if [receivedAtUtc] falls within the allowed reprocessing
  /// window for a contractual service window that ended at [windowEndUtc].
  ///
  /// The cutoff is [windowEndUtc] + [window] (inclusive).
  ///
  /// - [windowEndUtc]: The UTC end-time of the contractual service window.
  /// - [receivedAtUtc]: The server-side arrival time of the telemetry fact.
  /// - [window]: Override window size. Defaults to [defaultWindow] (48 hours).
  static bool isWithinReprocessingWindow({
    required DateTime windowEndUtc,
    required DateTime receivedAtUtc,
    Duration window = defaultWindow,
  }) {
    final cutoff = windowEndUtc.add(window);
    return !receivedAtUtc.isAfter(cutoff);
  }
}
