import 'package:equatable/equatable.dart';

import 'spoofing_signal.dart';

/// Value object representing the result of a spoofing analysis.
///
/// Implements [Equateable] to allow comparison in tests and domain events.
class SpoofingRiskScore extends Equatable {
  /// Risk score in Basis Points (0 to 10,000).
  /// 10,000 bps = 100% risk.
  final int scoreBps;

  /// List of signals detected in the analyzed window.
  final List<SpoofingSignal> signals;

  /// Default threshold for suspicion (Phase 8.8 definition).
  static const int defaultThresholdBps = 7000; // 70% in bps

  const SpoofingRiskScore({required this.scoreBps, required this.signals});

  /// Factory for a risk-free result.
  factory SpoofingRiskScore.zero() =>
      const SpoofingRiskScore(scoreBps: 0, signals: []);

  /// Whether the score exceeds the defined suspicion threshold.
  bool isSuspected({int thresholdBps = defaultThresholdBps}) =>
      scoreBps >= thresholdBps;

  @override
  List<Object?> get props => [scoreBps, signals];

  factory SpoofingRiskScore.fromJson(Map<String, dynamic> json) {
    final rawScore = json['score_bps'] ?? json['score'];
    final int score;
    if (rawScore is double) {
      score = (rawScore * 10000).toInt();
    } else {
      score = rawScore as int? ?? 0;
    }

    return SpoofingRiskScore(
      scoreBps: score,
      signals: (json['signals'] as List<dynamic>?)
              ?.map((s) => SpoofingSignal.values.firstWhere((e) => e.name == s))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'score_bps': scoreBps,
    'signals': signals.map((s) => s.name).toList(),
  };
}
