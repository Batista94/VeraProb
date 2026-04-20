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
  static const int _tamperBpsThreshold = 8000;
  static const int _networkIssueBpsThreshold = 3000;

  const HeartbeatClassifier();

  /// Classifies the device heartbeat given [gapSeconds] elapsed since last
  /// ping and [fleetActiveBps] (0–10,000) of the fleet still reporting.
  HeartbeatClassification classify(int gapSeconds, int fleetActiveBps) {
    if (gapSeconds <= _signalLostThresholdSeconds) {
      return HeartbeatClassification.normal;
    }
    if (fleetActiveBps >= _tamperBpsThreshold) {
      return HeartbeatClassification.deviceTamper;
    }
    if (fleetActiveBps <= _networkIssueBpsThreshold) {
      return HeartbeatClassification.networkIssue;
    }
    return HeartbeatClassification.unknown;
  }
}
