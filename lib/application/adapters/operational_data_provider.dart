import '../../domain/entities/vehicle_position.dart';

/// Adapter interface for ingesting raw vehicle GPS telemetry.
///
/// This abstracts the source of the data from the Normalization Layer.
/// The application can switch between:
/// 1. [SimulationDataProvider] (generates fake GPS pings for testing)
/// 2. [RealtimeDataProvider] (connects to actual hardware via WebSockets)
abstract interface class IOperationalDataProvider {
  /// Stream of raw, noisy GPS positions arriving from the fleet.
  Stream<List<VehiclePosition>> get positionStream;

  /// Starts the ingestion process (connects sockets, starts loops).
  Future<void> connect();

  /// Stops ingestion and cleans up resources.
  Future<void> disconnect();

  /// Whether the provider is currently active and receiving data.
  bool get isConnected;
}
