import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/trip.dart';
import 'trip_repository.dart';

class TripRepositoryImpl implements ITripRepository {
  final SupabaseClient _supabase;

  TripRepositoryImpl(this._supabase);

  String get _orgId {
    final orgId =
        _supabase.auth.currentSession?.user.appMetadata['org_id'] as String?;
    if (orgId == null) throw StateError('No organization in session JWT');
    return orgId;
  }

  @override
  Future<List<Trip>> getTrips() async {
    // Join with routes to get the human readable ID
    final response = await _supabase
        .from('trips_audit')
        .select('*, routes(gtfs_route_id)')
        .order('start_time', ascending: false);

    return (response as List).map((data) {
      final routeCode = data['routes'] != null
          ? data['routes']['gtfs_route_id']
          : data['route_id']; // Fallback

      return Trip(
        id: data['id'],
        routeId: routeCode,
        driverId: data['driver_id'],
        startTime: DateTime.parse(data['start_time']),
        endTime: data['end_time'] != null
            ? DateTime.parse(data['end_time'])
            : null,
        status: data['status'],
      );
    }).toList();
  }

  @override
  Future<Trip> startTrip(String driverId, String routeId) async {
    // Schema check: route_id in DB is UUID referencing routes(id).
    // Frontend passes "809U" (string code).
    // We must resolve route UUID from code or change schema to accept text.
    // OPTION 1: Change schema to TEXT for route_id (easier for MVP).
    // OPTION 2: Insert into routes table first if not exists.

    // For MVP robustness with "fictional data", let's assume route_id is the Code.
    // If schema enforces UUID, we fail.
    // Implementation Plan said:
    // CREATE TABLE public.routes (id UUID... gtfs_route_id TEXT... name TEXT...)
    // public.trips_audit (route_id UUID REFERENCES public.routes(id)...)

    // So we CANNOT verify insert "809U" into route_id (UUID).
    // We need to look up the route UUID by gtfs_route_id="809U" or name.
    // OR create a dummy route.

    // Workaround for MVP:
    // We will attempt to find a route with gtfs_route_id = routeId.
    // If not found, create it.

    String realRouteUUID;

    final routeRes = await _supabase
        .from('routes')
        .select('id')
        .eq('gtfs_route_id', routeId)
        .maybeSingle();

    if (routeRes == null) {
      // Create dummy route
      final newRoute = await _supabase
          .from('routes')
          .insert({
            'organization_id': _orgId,
            'gtfs_route_id': routeId,
            'short_name': routeId,
            'long_name': 'Linha $routeId',
            'agency_id': 'SPTRANS',
          })
          .select()
          .single();
      realRouteUUID = newRoute['id'];
    } else {
      realRouteUUID = routeRes['id'];
    }

    final response = await _supabase
        .from('trips_audit')
        .insert({
          'organization_id': _orgId,
          'driver_id': driverId,
          'route_id': realRouteUUID,
          'status': 'active',
          'source_type': 'manual',
        })
        .select()
        .single();

    return Trip(
      id: response['id'],
      routeId: routeId, // Return the code we passed
      driverId: response['driver_id'],
      startTime: DateTime.parse(response['start_time']),
      status: response['status'],
    );
  }

  @override
  Future<void> endTrip(String tripId) async {
    await _supabase
        .from('trips_audit')
        .update({
          'end_time': DateTime.now().toUtc().toIso8601String(),
          'status': 'completed',
        })
        .eq('id', tripId);
  }
}
