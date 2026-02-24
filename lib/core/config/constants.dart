/// Application-wide constants and configurable thresholds.
class AppConstants {
  AppConstants._();

  // ── Map Configuration ───────────────────────────────
  /// MapTiler dark style URL (free tier)
  static const String mapTileUrl =
      'https://api.maptiler.com/maps/dataviz-dark/{z}/{x}/{y}.png?key={key}';

  /// MapTiler API key (free tier — 100K requests/month)
  /// Replace with your own key from https://cloud.maptiler.com/
  static const String mapTilerKey = String.fromEnvironment(
    'MAPTILER_KEY',
    defaultValue: 'get_your_own_key',
  );

  /// Default map center: São Paulo, Brazil
  static const double defaultLatitude = -23.5505;
  static const double defaultLongitude = -46.6333;
  static const double defaultZoom = 13.0;

  // ── Operational Thresholds ──────────────────────────
  /// Delay in seconds before a trip is considered "delayed"
  static const int delayThresholdSeconds = 300; // 5 minutes

  /// Position age before it's considered "stale"
  static const Duration stalePositionThreshold = Duration(minutes: 2);

  /// Polling interval for simulated GTFS feed
  static const Duration gtfsPollingInterval = Duration(seconds: 15);

  // ── UI Constants ────────────────────────────────────
  /// Width of the trip sidebar in Command Center
  static const double tripSidebarWidth = 300.0;

  /// Width of the trip detail panel (slide-over)
  static const double tripDetailPanelWidth = 360.0;

  /// Height of the KPI bar
  static const double kpiBarHeight = 64.0;

  /// Height of the alert bar at the bottom
  static const double alertBarHeight = 36.0;
}
