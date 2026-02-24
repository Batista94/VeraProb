import 'dart:async';
import '../../domain/entities/vehicle_position.dart';
import '../../data/services/fleet_simulation_service.dart';
import '../../dev/performance_metrics.dart';
import 'operational_data_provider.dart';

/// Legacy adapter that wraps the existing [FleetSimulationService]
/// to implement the new [IOperationalDataProvider] interface.
///
/// Used when the app is running in 'simulation' mode (configured via AppConfig).
class SimulationDataProvider implements IOperationalDataProvider {
  final FleetSimulationService _simulationService;
  final Duration updateInterval;
  final PerformanceMetrics? metrics;

  StreamSubscription? _sub;
  final _controller = StreamController<List<VehiclePosition>>.broadcast();

  bool _isConnected = false;

  SimulationDataProvider(
    this._simulationService, {
    this.updateInterval = const Duration(seconds: 15),
    this.metrics,
  });

  @override
  Stream<List<VehiclePosition>> get positionStream => _controller.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    // Wire the simulation stream into our controller
    _sub = _simulationService.positionStream(interval: updateInterval).listen((
      data,
    ) {
      metrics?.markIngestion();
      _controller.add(data);
    }, onError: (e) => _controller.addError(e));
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    _isConnected = false;
  }
}
