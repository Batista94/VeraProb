/// Specific indicators used by the [SpoofingDetector] to calculate risk.
enum SpoofingSignal {
  /// Position remains invariant (> 5m variation) while device reports speed.
  staticPositionWhileMoving,

  /// [accuracyMeters] remains identically the same over multiple pings.
  /// Real GPS noise always produces small variations in accuracy.
  zeroEntropyAccuracy,

  /// Direction/Heading has near-zero variance over a 20+ ping window.
  /// Physically impossible for a moving vehicle.
  perfectLinearTrajectory,

  /// Trajectory matches a historical session with > 90% correlation.
  routeReplayDetected,

  /// Variação de velocidade excede o limite físico sem frenagem.
  impossibleAcceleration,
}
