import 'dart:math' show pow, sqrt;

import 'package:veraprob/domain/shared/geo_math.dart';

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
    int totalWeightedScoreBps = 0;

    // 1. Static Position while "Moving"
    if (_checkStaticPositionWithSpeed(facts)) {
      detectedSignals.add(SpoofingSignal.staticPositionWhileMoving);
      totalWeightedScoreBps += 5000; // 0.5 -> 50%
    }

    // 2. Zero Entropy in Accuracy (Phase 8.8 prioritized)
    if (_checkZeroEntropyAccuracy(facts)) {
      detectedSignals.add(SpoofingSignal.zeroEntropyAccuracy);
      totalWeightedScoreBps += 4000; // 0.4 -> 40%
    }

    // 3. Perfect Linear Trajectory (Heading Variance)
    if (_checkPerfectLinearTrajectory(facts)) {
      detectedSignals.add(SpoofingSignal.perfectLinearTrajectory);
      totalWeightedScoreBps += 3000; // 0.3 -> 30%
    }

    // 4. Impossible Position Jump (Teleport Guard — INV-18)
    if (_checkImpossiblePositionJump(facts)) {
      detectedSignals.add(SpoofingSignal.impossiblePositionJump);
      totalWeightedScoreBps += 8000; // 0.8 -> 80% — strongest single indicator
    }

    // 5. Temporal Anomaly (Chronological Integrity — INV-18)
    if (_checkTemporalAnomaly(facts)) {
      detectedSignals.add(SpoofingSignal.temporalAnomaly);
      totalWeightedScoreBps +=
          7000; // 0.7 -> 70% — replay / clock attack indicator
    }

    // 6. Excessive Temporal Gap (Tunnel/Bunker Attack — INV-18)
    if (_checkExcessiveTemporalGap(facts)) {
      detectedSignals.add(SpoofingSignal.excessiveTemporalGap);
      totalWeightedScoreBps += 8000; // 0.8 -> 80% — device tampering indicator
    }

    return SpoofingRiskScore(
      // Max score is 10,000 bps (100%)
      scoreBps: totalWeightedScoreBps.clamp(0, 10000),
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
    double maxDistanceM = 0; // Physical Metric - Double Required
    final List<double> allDistances = []; // Physical Metric - Double Required
    for (int i = 0; i < movingFacts.length; i++) {
      for (int j = i + 1; j < movingFacts.length; j++) {
        final d = GeoMath.haversineMeters(
          movingFacts[i].lat,
          movingFacts[i].lng,
          movingFacts[j].lat,
          movingFacts[j].lng,
        );
        allDistances.add(d);
        if (d > maxDistanceM) maxDistanceM = d;
      }
    }

    // Jiggle attack detection: calculate standard deviation
    if (allDistances.isNotEmpty) {
      final mean = allDistances.reduce((a, b) => a + b) / allDistances.length;
      final variance =
          allDistances.map((d) => pow(d - mean, 2)).reduce((a, b) => a + b) /
          allDistances.length;
      final stdDev = sqrt(variance);

      // Jiggle signature: low mean but high stdDev indicates artificial outlier
      if (mean < 1.0 && stdDev > 0.5) return true;
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

  /// Heuristic 4: [impossiblePositionJump]
  ///
  /// Detects teleportation: any consecutive pair of pings that implies a
  /// speed exceeding 4,167 cm/s (150 km/h — commercial vehicle hard limit).
  /// Strongest GPS-relay / teleport attack indicator (INV-18).
  bool _checkImpossiblePositionJump(List<CanonicalFact> facts) {
    const int maxCommercialSpeedCms =
        4167; // 150 km/h — Physical Metric - Double Required
    for (int i = 0; i < facts.length - 1; i++) {
      final a = facts[i];
      final b = facts[i + 1];
      final elapsedSeconds = b.gpsTimestamp
          .difference(a.gpsTimestamp)
          .inSeconds;
      final implied = GeoMath.impliedSpeedCms(
        a.lat,
        a.lng,
        b.lat,
        b.lng,
        elapsedSeconds,
      );
      if (implied != null && implied > maxCommercialSpeedCms) return true;
    }
    return false;
  }

  /// Heuristic 5: [temporalAnomaly]
  ///
  /// GPS timestamps must be strictly ascending. Any non-ascending pair
  /// indicates device clock manipulation, log replay, or timestamp injection
  /// (INV-18 Zero-Trust Telemetry / INV-6 UTC Mandatory).
  bool _checkTemporalAnomaly(List<CanonicalFact> facts) {
    for (int i = 0; i < facts.length - 1; i++) {
      if (!facts[i + 1].gpsTimestamp.isAfter(facts[i].gpsTimestamp)) {
        return true;
      }
    }
    return false;
  }

  /// Heuristic 6: [excessiveTemporalGap]
  ///
  /// Detects GPS blackout followed by impossible repositioning.
  /// Gap > 15 min + distance > 50 km indicates device tampering or relay attack.
  bool _checkExcessiveTemporalGap(List<CanonicalFact> facts) {
    const int maxGapMinutes = 15;
    const double maxDistanceKm = 50.0; // Physical Metric - Double Required

    for (int i = 0; i < facts.length - 1; i++) {
      final gap = facts[i + 1].gpsTimestamp.difference(facts[i].gpsTimestamp);
      if (gap.inMinutes > maxGapMinutes) {
        final distM = GeoMath.haversineMeters(
          facts[i].lat,
          facts[i].lng,
          facts[i + 1].lat,
          facts[i + 1].lng,
        );
        if (distM / 1000 > maxDistanceKm) return true;
      }
    }
    return false;
  }
}
