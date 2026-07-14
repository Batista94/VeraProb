import 'package:veraprob/domain/shared/i_trip_repository.dart';
import 'package:veraprob/domain/entities/trip.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

/// Supabase implementation of [ITripRepository].
///
/// Lives in infrastructure so that [lib/features/] stays free of Supabase deps.
class TripRepositoryImpl extends BasePostgresRepository
    implements ITripRepository {
  final IDateTimeProvider _dateTimeProvider;

  TripRepositoryImpl(super.client, this._dateTimeProvider);

  @override
  Future<List<Trip>> getTrips() {
    return withErrorHandler('trip', null, () async {
      final response = await client
          .from('trips_audit')
          .select('*, routes(gtfs_route_id)')
          .order('start_time', ascending: false);

      return (response as List)
          .map((data) => _fromSupabase(data as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<Trip> startTrip(String driverId, String routeId) async {
    final routeRes = await withErrorHandler(
      'trip',
      null,
      () => client
          .from('routes')
          .select('id')
          .eq('gtfs_route_id', routeId)
          .maybeSingle(),
    );

    final String realRouteUUID;
    if (routeRes == null) {
      final newRoute = await withErrorHandler(
        'trip',
        null,
        () => client
            .from('routes')
            .insert({
              'organization_id': sessionOrgId,
              'gtfs_route_id': routeId,
              'short_name': routeId,
              'long_name': 'Linha $routeId',
              'agency_id': 'SPTRANS',
            })
            .select()
            .single(),
      );
      realRouteUUID = newRoute['id'] as String;
    } else {
      realRouteUUID = routeRes['id'] as String;
    }

    return withErrorHandler('trip', null, () async {
      final response = await client
          .from('trips_audit')
          .insert({
            'organization_id': sessionOrgId,
            'driver_id': driverId,
            'route_id': realRouteUUID,
            'status': 'active',
            'source_type': 'manual',
          })
          .select()
          .single();

      return _fromSupabase(response);
    });
  }

  @override
  Future<void> endTrip(String tripId) {
    return withErrorHandler(
      'trip',
      tripId,
      () => client
          .from('trips_audit')
          .update({
            'end_time': _dateTimeProvider.nowUtc().toIso8601String(),
            'status': 'completed',
          })
          .eq('id', tripId),
    );
  }

  static Trip _fromSupabase(Map<String, dynamic> data) {
    final routeCode = data['routes'] != null
        ? (data['routes'] as Map)['gtfs_route_id']
        : data['route_id'];

    return Trip(
      id: data['id'] as String,
      routeId: routeCode as String,
      driverId: data['driver_id'] as String,
      startTime: DateTime.parse(data['start_time'] as String).toUtc(),
      endTime: data['end_time'] != null
          ? DateTime.parse(data['end_time'] as String).toUtc()
          : null,
      status: data['status'] as String,
    );
  }
}
