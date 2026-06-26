import 'dart:async';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';
import 'gtfs_realtime_service.dart';

abstract class IVehiclePositionService {
  Stream<List<VehiclePosition>> getVehiclePositions();
  Future<void> sendVehiclePosition(VehiclePosition position);
}

class VehicleRepository implements IVehiclePositionService {
  final GtfsRealtimeService _gtfsService;

  // Cache API positions to compare timestamps
  final Map<String, VehiclePosition> _apiPositionsCache = {};

  VehicleRepository(this._gtfsService);

  @override
  Stream<List<VehiclePosition>> getVehiclePositions() {
    // 1. Stream from API (The Truth)
    return _gtfsService.getVehiclePositions().transform(
      StreamTransformer.fromHandlers(
        handleData:
            (
              List<VehiclePosition> positions,
              EventSink<List<VehiclePosition>> sink,
            ) {
              final List<VehiclePosition> filteredPositions = [];

              for (final position in positions) {
                final cached = _apiPositionsCache[position.tripId];
                if (cached == null ||
                    position.timestamp.isAfter(cached.timestamp)) {
                  _apiPositionsCache[position.tripId] = position;
                  filteredPositions.add(position);
                }
              }

              if (filteredPositions.isNotEmpty) {
                sink.add(filteredPositions);
              }
            },
      ),
    );
  }

  @override
  Future<void> sendVehiclePosition(VehiclePosition position) async {
    // For now, simulate sending to GTFS-RT feed
    // In production, send to GTFS-RT feed
    final Map<String, dynamic> payload = {
      'trip_id': position.tripId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': position.timestamp.toIso8601String(),
      'route_name': position.routeName,
    };

    try {
      // Local development mode: log upload trace
      LoggerService().log(
        '🚀 UPLOAD [${position.source}] Trip ${position.tripId}: ${position.latitude}, ${position.longitude} - payload: $payload',
      );
    } catch (e) {
      LoggerService().error('Error sending position', error: e);
    }
  }
}
