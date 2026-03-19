import 'package:equatable/equatable.dart';

import 'spoofing_signal.dart';

/// Value object representing the result of a spoofing analysis.
///
/// Implements [Equateable] to allow comparison in tests and domain events.
class SpoofingRiskScore extends Equatable {
  /// Raw risk score between 0.0 and 1.0.
  final double score;

  /// List of signals detected in the analyzed window.
  final List<SpoofingSignal> signals;

  /// Default threshold for suspicion (Phase 8.8 definition).
  static const double defaultThreshold = 0.7;

  const SpoofingRiskScore({
    required this.score,
    required this.signals,
  });

  /// Factory for a risk-free result.
  factory SpoofingRiskScore.zero() =>
      const SpoofingRiskScore(score: 0.0, signals: []);

  /// Whether the score exceeds the defined suspicion threshold.
  bool isSuspected({double threshold = defaultThreshold}) => score >= threshold;

  @override
  List<Object?> get props => [score, signals];

  Map<String, dynamic> toJson() => {
    'score': score,
    'signals': signals.map((s) => s.name).toList(),
  };
}
