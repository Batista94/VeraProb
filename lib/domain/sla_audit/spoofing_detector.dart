import 'dart:math' show pow, sqrt;

import 'package:veraprob/core/utils/geo_math.dart';

import 'canonical_fact.dart';
import 'spoofing_risk_score.dart';
import 'spoofing_signal.dart';

/// Stateless domain service that analyzes a window of [CanonicalFact]
/// for active GPS spoofing (active adversarial manipulation).
///
/// Implements Phase 8.8 Anti-Spoofing heuristics.
class SpoofingDetector {
  const SpoofingDetector();

  /// Analyzes a time-ordered window of [facts] for a single device.
  ///
  /// Returns a [SpoofingRiskScore] representing the collective risk
  /// from multiple heuristics.
  SpoofingRiskScore analyze(List<CanonicalFact> facts) {
    if (facts.length < 5) return SpoofingRiskScore.zero();

    final List<SpoofingSignal> detectedSignals = [];
    double totalWeightedScore = 0.0;

    // 1. Static Position while "Moving"
    if (_checkStaticPositionWithSpeed(facts)) {
      detectedSignals.add(SpoofingSignal.staticPositionWhileMoving);
      totalWeightedScore += 0.5;
    }

    // 2. Zero Entropy in Accuracy (Phase 8.8 prioritized)
    if (_checkZeroEntropyAccuracy(facts)) {
      detectedSignals.add(SpoofingSignal.zeroEntropyAccuracy);
      totalWeightedScore += 0.4;
    }

    // 3. Perfect Linear Trajectory (Heading Variance)
    if (_checkPerfectLinearTrajectory(facts)) {
      detectedSignals.add(SpoofingSignal.perfectLinearTrajectory);
      totalWeightedScore += 0.3;
    }

    return SpoofingRiskScore(
      // Max score is 1.0
      score: totalWeightedScore.clamp(0.0, 1.0),
      signals: detectedSignals,
    );
  }

  /// Heuristic 1: [staticPositionWhileMoving]
  /// Detects if the device reports a significant speed but remains at the
  /// exact same coordinates (+/- 1m) for over 5 minutes.
  bool _checkStaticPositionWithSpeed(List<CanonicalFact> facts) {
    if (facts.isEmpty) return false;

    final windowDuration = facts.last.gpsTimestamp.difference(
      facts.first.gpsTimestamp,
    );
    if (windowDuration.inMinutes < 5) return false;

    // Use only facts that report speed > 5 km/h (138 cm/s)
    final movingFacts = facts.where((f) => (f.speedCms ?? 0) > 138).toList();
    if (movingFacts.length < 5) return false;

    // Check distance between any two points in the window
    double maxDistanceM = 0;
    for (int i = 0; i < movingFacts.length; i++) {
      for (int j = i + 1; j < movingFacts.length; j++) {
        final d = GeoMath.haversineMeters(
          movingFacts[i].lat,
          movingFacts[i].lng,
          movingFacts[j].lat,
          movingFacts[j].lng,
        );
        if (d > maxDistanceM) maxDistanceM = d;
      }
    }

    // If never moved more than 2 meters during "motion", it's spoofing.
    return maxDistanceM < 2.0;
  }

  /// Heuristic 2: [zeroEntropyAccuracy]
  /// Real GPS accuracy always oscillates slightly due to ionospheric noise
  /// and timing. If it stays at EXACTLY the same value in 10+ pings, it's fake.
  bool _checkZeroEntropyAccuracy(List<CanonicalFact> facts) {
    final values = facts
        .where((f) => f.accuracyMeters != null)
        .map((f) => f.accuracyMeters!)
        .toList();
    if (values.length < 10) return false;

    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
        values.length;
    final stdDev = sqrt(variance);

    // StdDev < 0.001 is physically impossible for consumer or commercial GPS over 10 pings
    return stdDev < 0.001;
  }

  /// Heuristic 3: [perfectLinearTrajectory]
  /// Detects if the heading reports 0 variance. Even on highways, minor
  /// road curves and vibration lead to minor fluctuations in heading.
  bool _checkPerfectLinearTrajectory(List<CanonicalFact> facts) {
    final headings = facts
        .where((f) => f.headingDegrees != null)
        .map((f) => f.headingDegrees!.toDouble())
        .toList();
    if (headings.length < 15) return false;

    // Simple variance check on heading
    final mean = headings.reduce((a, b) => a + b) / headings.length;
    final variance =
        headings.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
        headings.length;
    final stdDev = sqrt(variance);

    // Moving vehicle with exactly identical heading in 15+ pings
    return stdDev < 0.1;
  }
}
