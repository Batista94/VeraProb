import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/vehicle_position.dart';
import '../services/gtfs_realtime_service.dart';

abstract class IVehiclePositionService {
  Stream<List<VehiclePosition>> getVehiclePositions();
  Future<void> sendVehiclePosition(VehiclePosition position);
}

class VehicleRepository implements IVehiclePositionService {
  // ignore: unused_field
  final SupabaseClient _supabase;
  final GtfsRealtimeService _gtfsService;

  // Cache API positions to compare timestamps
  final Map<String, VehiclePosition> _apiPositionsCache = {};

  VehicleRepository(this._supabase, this._gtfsService);

  @override
  Stream<List<VehiclePosition>> getVehiclePositions() {
    // 1. Stream from API (The Truth)
    final apiStream = _gtfsService.getVehiclePositions().map((positions) {
      for (var pos in positions) {
        _apiPositionsCache[pos.tripId] = pos;
      }
      return positions;
    });

    // 2. Stream from Supabase (Crowdsourcing)
    // In a real app, we would listen to a Supabase channel
    // For now, we'll simulate it or keep it empty until DB is ready
    final crowdsourceStream = Stream<List<VehiclePosition>>.periodic(
      const Duration(seconds: 5),
      (_) => [], // Placeholder for Supabase data
    );

    // Merge streams logic (simplified for MVP)
    // We basically want to emit whenever we get fresh data,
    // prioritizing API data if it exists and is recent.

    // ignore: unused_local_variable
    final _ = crowdsourceStream; // Stub for now

    return apiStream;
  }

  @override
  Future<void> sendVehiclePosition(VehiclePosition position) async {
    // ignore: unused_local_variable
    final data = {
      'trip_id': position.tripId,
      'location': 'POINT(${position.longitude} ${position.latitude})',
      'speed': position.speed,
      'heading': position.heading,
      'source': position.source,
      'timestamp': position.timestamp.toIso8601String(),
      'route_name': position.routeName,
    };

    try {
      // Uncomment to enable real Supabase insert
      // await _supabase.from('vehicle_positions').insert(data);

      // For MVP without creds, just log clearly
      // ignore: avoid_print
      print(
        '🚀 UPLOAD [${position.source}] Trip ${position.tripId}: ${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      // ignore: avoid_print
      print('Error sending position: $e');
    }
  }
}
