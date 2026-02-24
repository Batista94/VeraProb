/// Command Center Key Performance Indicators.
/// Pure data contract representing aggregated metrics for the top KPI Bar.
class CommandCenterKPIs {
  /// Percentage of completed or active trips that are on time (0.0 to 1.0)
  final double globalPunctuality;

  /// Total number of active vehicles currently broadcasting data
  final int activeVehicles;

  /// Percentage of active vehicles currently suffering from signal loss (0.0 to 1.0)
  final double signalLossRate;

  /// Absolute number of critical incidents currently open
  final int openIncidents;

  const CommandCenterKPIs({
    this.globalPunctuality = 1.0,
    this.activeVehicles = 0,
    this.signalLossRate = 0.0,
    this.openIncidents = 0,
  });

  CommandCenterKPIs copyWith({
    double? globalPunctuality,
    int? activeVehicles,
    double? signalLossRate,
    int? openIncidents,
  }) {
    return CommandCenterKPIs(
      globalPunctuality: globalPunctuality ?? this.globalPunctuality,
      activeVehicles: activeVehicles ?? this.activeVehicles,
      signalLossRate: signalLossRate ?? this.signalLossRate,
      openIncidents: openIncidents ?? this.openIncidents,
    );
  }
}
