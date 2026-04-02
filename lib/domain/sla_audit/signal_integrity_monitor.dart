import 'package:equatable/equatable.dart';

/// Severity classification for a telemetry gap.
///
/// - [warning]: gap > 120s but ≤ 600s. Degraded signal quality.
/// - [critical]: gap > 600s. Near-total data silence.
enum GapSeverity {
  /// Gap > 120s and ≤ 600s.
  warning,

  /// Gap > 600s (10 min). Severe data loss — possible hardware failure.
  critical,
}

/// A detected telemetry gap exceeding the 120s Data Silence threshold.
///
/// Immutable value object (INV-4: zero Flutter/Supabase dependencies).
class DataSilenceGap extends Equatable {
  /// UTC timestamp when the gap started (last received ping before silence).
  final DateTime startedAtUtc;

  /// UTC timestamp when the gap ended (first ping after silence).
  final DateTime endedAtUtc;

  /// Duration of the gap in seconds.
  final int durationSeconds;

  /// Severity classification based on gap duration.
  final GapSeverity severity;

  const DataSilenceGap({
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.durationSeconds,
    required this.severity,
  });

  @override
  List<Object?> get props => [startedAtUtc, endedAtUtc, durationSeconds];
}

/// Result of the signal integrity analysis for a telemetry stream.
///
/// Contains detected [gaps] and an overall [integrityScore] (0–100).
/// Links directly to the WS-1 Double Confirmation gate via
/// [requiresDoubleConfirmation].
class SignalIntegrityReport extends Equatable {
  /// Detected Data Silence gaps (> 120s), ordered chronologically.
  final List<DataSilenceGap> gaps;

  /// Overall signal integrity score (0–100).
  ///
  /// 100 = all intervals ≤ 120s (perfect signal).
  /// 0 = no data or entire stream is one silent gap.
  ///
  /// Formula: `max(0, 100 - (totalSilentSeconds / totalSpanSeconds * 100))`
  final int integrityScore;

  /// Total duration of all silent gaps in seconds.
  final int totalSilentSeconds;

  /// Total span of the telemetry stream in seconds (first → last ping).
  final int totalSpanSeconds;

  const SignalIntegrityReport({
    required this.gaps,
    required this.integrityScore,
    required this.totalSilentSeconds,
    required this.totalSpanSeconds,
  });

  /// Whether the WS-1 Double Confirmation gate should be activated.
  ///
  /// Returns `true` when [integrityScore] < 70, requiring the auditor
  /// to explicitly confirm before sealing a verdict.
  bool get requiresDoubleConfirmation => integrityScore < 70;

  @override
  List<Object?> get props => [
    gaps,
    integrityScore,
    totalSilentSeconds,
    totalSpanSeconds,
  ];
}

/// Pure domain service that analyzes a telemetry timestamp stream for
/// signal integrity.
///
/// **The 120s Rule:** any gap between consecutive GPS timestamps that
/// exceeds 120 seconds is classified as 'Data Silence'.
///
/// **Scoring:** `integrityScore = max(0, 100 - (silentTime / totalSpan × 100))`
///
/// **Invariants:**
/// - INV-4: zero Flutter/Supabase dependencies.
/// - INV-18: pure Dart, WASM-ready.
/// - Deterministic: same inputs → same output.
class SignalIntegrityMonitor {
  /// Data Silence threshold in seconds. Gaps > this value are flagged.
  static const int silenceThresholdSeconds = 120;

  /// Critical severity threshold in seconds.
  static const int criticalThresholdSeconds = 600;

  const SignalIntegrityMonitor();

  /// Analyzes a list of telemetry timestamps and produces a
  /// [SignalIntegrityReport].
  ///
  /// [timestamps] — UTC timestamps of received pings. Will be sorted
  /// internally; callers do not need to pre-sort.
  ///
  /// Returns a report with [integrityScore] = 0 if the list is empty,
  /// and 100 if there is a single timestamp (no gaps possible).
  SignalIntegrityReport analyze(List<DateTime> timestamps) {
    if (timestamps.isEmpty) {
      return const SignalIntegrityReport(
        gaps: [],
        integrityScore: 0,
        totalSilentSeconds: 0,
        totalSpanSeconds: 0,
      );
    }

    if (timestamps.length == 1) {
      return const SignalIntegrityReport(
        gaps: [],
        integrityScore: 100,
        totalSilentSeconds: 0,
        totalSpanSeconds: 0,
      );
    }

    // Sort chronologically — tolerate unsorted input.
    final sorted = List<DateTime>.from(timestamps)..sort();

    final gaps = <DataSilenceGap>[];
    var totalSilentSeconds = 0;

    for (var i = 1; i < sorted.length; i++) {
      final gapSeconds = sorted[i].difference(sorted[i - 1]).inSeconds;

      if (gapSeconds > silenceThresholdSeconds) {
        final severity = gapSeconds > criticalThresholdSeconds
            ? GapSeverity.critical
            : GapSeverity.warning;

        gaps.add(
          DataSilenceGap(
            startedAtUtc: sorted[i - 1],
            endedAtUtc: sorted[i],
            durationSeconds: gapSeconds,
            severity: severity,
          ),
        );

        totalSilentSeconds += gapSeconds;
      }
    }

    final totalSpanSeconds = sorted.last.difference(sorted.first).inSeconds;

    // Score = max(0, 100 - (silentFraction * 100))
    final int integrityScore;
    if (totalSpanSeconds == 0) {
      integrityScore = 100; // All timestamps identical → perfect score.
    } else {
      final silentFraction = totalSilentSeconds / totalSpanSeconds;
      integrityScore = (100 - (silentFraction * 100)).round().clamp(0, 100);
    }

    return SignalIntegrityReport(
      gaps: gaps,
      integrityScore: integrityScore,
      totalSilentSeconds: totalSilentSeconds,
      totalSpanSeconds: totalSpanSeconds,
    );
  }
}
