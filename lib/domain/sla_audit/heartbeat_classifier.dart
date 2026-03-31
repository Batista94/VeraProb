import 'heartbeat_classification.dart';

/// Pure domain service that classifies a device's silence as
/// network failure vs hardware tamper/sabotage.
///
/// **Heuristic:**
/// - `gapSeconds ≤ 90` → [HeartbeatClassification.normal]
/// - `gapSeconds > 90 AND fleetActiveRatio ≥ 0.8` → [HeartbeatClassification.deviceTamper]
///   (most fleet still online → this device was isolated/sabotaged)
/// - `gapSeconds > 90 AND fleetActiveRatio ≤ 0.3` → [HeartbeatClassification.networkIssue]
///   (most fleet also offline → network outage)
/// - otherwise → [HeartbeatClassification.unknown]
///
/// No Flutter or Supabase dependencies (INV-18).
class HeartbeatClassifier {
  static const int _signalLostThresholdSeconds = 90;
  static const double _tamperRatioThreshold = 0.8;
  static const double _networkIssueRatioThreshold = 0.3;

  const HeartbeatClassifier();

  /// Classifies the device heartbeat given [gapSeconds] elapsed since last
  /// ping and [fleetActiveRatio] (0.0–1.0) of the fleet still reporting.
  HeartbeatClassification classify(int gapSeconds, double fleetActiveRatio) {
    if (gapSeconds <= _signalLostThresholdSeconds) {
      return HeartbeatClassification.normal;
    }
    if (fleetActiveRatio >= _tamperRatioThreshold) {
      return HeartbeatClassification.deviceTamper;
    }
    if (fleetActiveRatio <= _networkIssueRatioThreshold) {
      return HeartbeatClassification.networkIssue;
    }
    return HeartbeatClassification.unknown;
  }
}
