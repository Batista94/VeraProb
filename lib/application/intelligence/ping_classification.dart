import 'package:veraprob/domain/entities/vehicle_position.dart';

/// Reason a [RawTelemetryPing] was rejected by sensor sanitization.
///
/// Each value maps to one hardware-validation heuristic in
/// [TelemetryNormalizer]. Used for forensic auditability of dropped packets.
enum PingRejectionReason {
  /// Reported accuracy radius exceeds the configured maximum.
  lowAccuracy,

  /// Accuracy below physical noise floor (< 0.001 m) — emulator/Fake-GPS
  /// signature (INV-18).
  emulatorSignature,

  /// Haversine implied speed between this and the last valid ping exceeds
  /// the physical maximum — teleport artefact (INV-18).
  impossibleSpeedJump,

  /// Identical timestamp to the last valid ping but a non-trivial position
  /// delta — physically impossible glitch.
  sameTimestampMovement,
}

/// Result of classifying a single raw telemetry ping.
///
/// Sealed Result type mirroring the pattern in
/// `domain/sla_audit/telegram/compliance_check_result.dart`. Lets the caller
/// distinguish *why* a ping was dropped instead of an opaque `null`.
sealed class PingClassification {
  const PingClassification();
}

/// Ping passed all sensor checks — carries the clean [VehiclePosition].
class PingAccepted extends PingClassification {
  final VehiclePosition position;

  const PingAccepted(this.position);
}

/// Ping failed a sensor check — carries the [PingRejectionReason].
class PingRejected extends PingClassification {
  final PingRejectionReason reason;

  const PingRejected(this.reason);
}
