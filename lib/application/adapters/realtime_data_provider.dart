import 'dart:async';
import '../../domain/entities/vehicle_position.dart';
import 'operational_data_provider.dart';

/// Real-time adapter that will connect to actual vehicle hardware (hardware integration).
///
/// For now, this is a stub implementation that throws UnimplementedError
/// or simply yields empty lists, until the hardware team provides the WS endpoint.
class RealtimeDataProvider implements IOperationalDataProvider {
  final _controller = StreamController<List<VehiclePosition>>.broadcast();
  bool _isConnected = false;

  @override
  Stream<List<VehiclePosition>> get positionStream => _controller.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    // TODO: Initialize Supabase Realtime channel or raw WebSocket connection to IoT Hub.
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    // TODO: Teardown sockets
    _isConnected = false;
  }
}
