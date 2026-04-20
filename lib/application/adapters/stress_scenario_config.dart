class StressScenarioConfig {
  /// The deterministic seed for the scenario.
  /// Used to ensure reproducible random generation of trips, positions, and incidents.
  final int seed;

  /// The number of vehicles to simulate.
  final int vehicleCount;

  /// Probability of a vehicle encountering a critical incident
  /// (off-route, emergency, etc.) per tick.
  /// Unit: BPS ($10000 = 100%).
  final int incidentProbability;

  /// Probability of a vehicle experiencing connectivity issues
  /// (degraded or signal lost) per tick.
  /// Unit: BPS ($10000 = 100%).
  final int signalLossProbability;

  const StressScenarioConfig({
    required this.seed,
    this.vehicleCount = 8,
    this.incidentProbability = 500,
    this.signalLossProbability = 500,
  });

  /// A pre-defined stress scenario for 100 vehicles.
  factory StressScenarioConfig.stress100() {
    return const StressScenarioConfig(
      seed: 1337,
      vehicleCount: 100,
      incidentProbability: 1000,
      signalLossProbability: 1000,
    );
  }

  /// A pre-defined extreme stress scenario for 250 vehicles.
  factory StressScenarioConfig.extreme250() {
    return const StressScenarioConfig(
      seed: 42069,
      vehicleCount: 250,
      incidentProbability: 1500,
      signalLossProbability: 1500,
    );
  }
}
