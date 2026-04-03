/// Nested read model for a single data silence gap.
class DataSilenceGapView {
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final int durationSeconds;
  final String severity;

  const DataSilenceGapView({
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.durationSeconds,
    required this.severity,
  });
}

/// Read model for signal integrity analysis used in presentation layer.
///
/// [integrityScore] is int (0–100). [totalSilentSeconds] and
/// [totalSpanSeconds] are int (no fractional seconds).
class SignalIntegrityView {
  final List<DataSilenceGapView> gaps;

  /// Overall signal quality score (0–100, integer).
  final int integrityScore;
  final int totalSilentSeconds;
  final int totalSpanSeconds;
  final bool requiresDoubleConfirmation;

  const SignalIntegrityView({
    required this.gaps,
    required this.integrityScore,
    required this.totalSilentSeconds,
    required this.totalSpanSeconds,
    required this.requiresDoubleConfirmation,
  });
}
