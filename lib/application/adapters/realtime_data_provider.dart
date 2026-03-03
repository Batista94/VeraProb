import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/config/supabase_client.dart';
import '../../domain/entities/vehicle_position.dart';
import 'operational_data_provider.dart';

/// Real-time adapter that will connect to actual vehicle hardware (hardware integration).
///
/// For now, this is a stub implementation that throws UnimplementedError
/// or simply yields empty lists, until the hardware team provides the WS endpoint.
class RealtimeDataProvider implements IOperationalDataProvider {
  final _controller = StreamController<List<VehiclePosition>>.broadcast();
  RealtimeChannel? _channel;
  bool _isConnected = false;

  @override
  Stream<List<VehiclePosition>> get positionStream => _controller.stream;

  @override
  bool get isConnected => _isConnected;

  @override
  Future<void> connect() async {
    if (_isConnected) return;

    // Pending: Finalize channel name with hardware team
    _channel = supabase.channel('fleet-live-positions');

    _channel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicle_positions',
          callback: (payload) {
            // Normalization logic would go here
          },
        )
        .subscribe();

    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    if (!_isConnected) return;
    await _channel?.unsubscribe();
    _channel = null;
    _isConnected = false;
  }
}
