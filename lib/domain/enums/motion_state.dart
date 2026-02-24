/// Real-time motion classification of a vehicle, derived from
/// smoothed GPS telemetry — never from raw pings.
enum MotionState {
  /// Vehicle is actively moving (smoothedSpeed > 8 km/h).
  moving,

  /// Vehicle speed is between 0–8 km/h for > 30 s (congestion).
  slowTraffic,

  /// Vehicle is stationary but NOT near a known stop.
  stopped,

  /// Vehicle is stationary AND within 50 m of a known stop.
  dwellingAtStop;

  String get label {
    switch (this) {
      case MotionState.moving:
        return 'Em Movimento';
      case MotionState.slowTraffic:
        return 'Trânsito Lento';
      case MotionState.stopped:
        return 'Parado';
      case MotionState.dwellingAtStop:
        return 'No Ponto';
    }
  }

  /// Whether the vehicle is considered effectively stopped.
  bool get isStationary =>
      this == MotionState.stopped || this == MotionState.dwellingAtStop;
}
