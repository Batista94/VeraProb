import 'package:equatable/equatable.dart';

/// Classification of why a device stopped reporting telemetry.
///
/// Used by [HeartbeatClassifier] to distinguish between network-wide
/// outages and isolated device tampering (INV-16 Zero-Trust).
enum HeartbeatClassification {
  /// Device is reporting within the expected signal window (≤ 90s gap).
  normal,

  /// Device gap > 90s AND most of the fleet is still online.
  /// Indicates isolated device failure or physical tamper/sabotage.
  deviceTamper,

  /// Device gap > 90s AND most of the fleet is also offline.
  /// Indicates a network-wide connectivity issue, not isolated tampering.
  networkIssue,

  /// Device gap > 90s BUT fleet ratio is in the ambiguous mid-range (0.3–0.8).
  /// Requires manual auditor review.
  unknown,
}

/// Value object representing the heartbeat health of a single device.
///
/// Pure domain VO — no Flutter or Supabase dependencies (INV-18).
/// All timestamps are UTC (INV-9).
class DeviceHeartbeatStatus extends Equatable {
  /// Logical asset identifier for the device.
  final String assetId;

  /// UTC timestamp of the last received telemetry ping.
  final DateTime lastSeenAtUtc;

  /// Elapsed seconds since [lastSeenAtUtc].
  final int gapSeconds;

  /// Classification result from [HeartbeatClassifier].
  final HeartbeatClassification classification;

  /// Ratio of fleet devices actively reporting at the time of evaluation.
  /// Range: 0.0 (all offline) → 1.0 (all online).
  final double fleetActiveRatio;

  const DeviceHeartbeatStatus({
    required this.assetId,
    required this.lastSeenAtUtc,
    required this.gapSeconds,
    required this.classification,
    required this.fleetActiveRatio,
  });

  @override
  List<Object?> get props => [
    assetId,
    lastSeenAtUtc,
    gapSeconds,
    classification,
    fleetActiveRatio,
  ];
}
