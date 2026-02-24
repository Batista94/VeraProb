class StressScenarioConfig {
  /// The deterministic seed for the scenario.
  /// Used to ensure reproducible random generation of trips, positions, and incidents.
  final int seed;

  /// The number of vehicles to simulate.
  final int vehicleCount;

  /// Probability (0.0 to 1.0) of a vehicle encountering a critical incident
  /// (off-route, emergency, etc.) per tick.
  final double incidentProbability;

  /// Probability (0.0 to 1.0) of a vehicle experiencing connectivity issues
  /// (degraded or signal lost) per tick.
  final double signalLossProbability;

  const StressScenarioConfig({
    required this.seed,
    this.vehicleCount = 8,
    this.incidentProbability = 0.05,
    this.signalLossProbability = 0.05,
  });

  /// A pre-defined stress scenario for 100 vehicles.
  factory StressScenarioConfig.stress100() {
    return const StressScenarioConfig(
      seed: 1337,
      vehicleCount: 100,
      incidentProbability: 0.1,
      signalLossProbability: 0.1,
    );
  }

  /// A pre-defined extreme stress scenario for 250 vehicles.
  factory StressScenarioConfig.extreme250() {
    return const StressScenarioConfig(
      seed: 42069,
      vehicleCount: 250,
      incidentProbability: 0.15,
      signalLossProbability: 0.15,
    );
  }
}
