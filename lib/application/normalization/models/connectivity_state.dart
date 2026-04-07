/// Signal quality classification based on time since last GPS ping.
enum ConnectivityState {
  /// Last ping received < 30 s ago.
  healthy,

  /// Last ping received between 30 s and 90 s ago.
  degraded,

  /// No ping received for > 90 s.
  signalLost;

  String get label {
    switch (this) {
      case ConnectivityState.healthy:
        return 'Sinal OK';
      case ConnectivityState.degraded:
        return 'Sinal Fraco';
      case ConnectivityState.signalLost:
        return 'Sem Sinal';
    }
  }

  /// Visual confidence factor: 1.0 = perfect, 0.0 = no signal.
  double get confidence {
    // Physical Metric - Double Required
    switch (this) {
      case ConnectivityState.healthy:
        return 1.0;
      case ConnectivityState.degraded:
        return 0.5;
      case ConnectivityState.signalLost:
        return 0.0;
    }
  }
}
