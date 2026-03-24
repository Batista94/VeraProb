import 'dart:async';
import '../../data/services/fleet_simulation_service.dart';
import '../../domain/entities/vehicle_position.dart';
import 'operational_data_provider.dart';

/// Adapter that connects the [FleetSimulationService] to the operational data pipeline.
///
/// This allows the Audit Engine to receive simulated telemetry as if it were
/// coming from a real-time source.
class SimulationDataProvider implements IOperationalDataProvider {
  final FleetSimulationService _simulation;
  final _controller = StreamController<List<VehiclePosition>>.broadcast();
  StreamSubscription<List<VehiclePosition>>? _subscription;
  bool _isConnected = false;

  SimulationDataProvider(this._simulation);

  @override
  Stream<List<VehiclePosition>> get positionStream => _controller.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    _subscription = _simulation.positionStream().listen((positions) {
      _controller.add(positions);
    });

    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected) return;
    await _subscription?.cancel();
    _subscription = null;
    _isConnected = false;
  }
}
