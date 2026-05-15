import 'dart:async';
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';

/// Service acting as a bridge for Telemetry.
/// In Sprint 5, this uses Dart Streams in-memory to connect the Driver App
/// to the OCC locally. In the future, this will use Supabase Realtime.
class TelemetryService {
  final _rawPingController = StreamController<RawTelemetryPing>.broadcast();
  final _cleanPositionController =
      StreamController<VehiclePosition>.broadcast();

  final TelemetryNormalizer _normalizer;

  // Track active emitting vehicles
  final Map<String, bool> _activeEmitters = {};

  TelemetryService({TelemetryNormalizer? normalizer})
    : _normalizer = normalizer ?? TelemetryNormalizer() {
    // Wire up the Normalizer filtering
    _rawPingController.stream.listen((ping) {
      final cleanPosition = _normalizer.processPing(ping);
      if (cleanPosition != null) {
        _cleanPositionController.add(cleanPosition);
      }
    });
  }

  /// Appends a raw ping from the GPS hardware/driver app into the purgatory stream.
  void pushPing(RawTelemetryPing ping) {
    _rawPingController.add(ping);
    _activeEmitters[ping.vehicleId] = true;
  }

  /// Exposes the stream of CLEAN, filtered positions that the OCC/SituationEngine will consume
  Stream<VehiclePosition> get cleanPositionsStream =>
      _cleanPositionController.stream;

  /// Helper to check if a vehicle has ever emitted to this service
  bool isVehicleEmitting(String vehicleId) =>
      _activeEmitters[vehicleId] ?? false;

  void dispose() {
    _rawPingController.close();
    _cleanPositionController.close();
  }
}
