import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/shared/i_trip_repository.dart';
import 'package:veraprob/domain/entities/trip.dart';
import 'package:veraprob/infrastructure/shared/mappers/trip_mapper.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';

/// Supabase implementation of [ITripRepository].
///
/// Lives in infrastructure so that [lib/features/] stays free of Supabase deps.
class TripRepositoryImpl
    with PostgresErrorInterceptor
    implements ITripRepository {
  final SupabaseClient _supabase;
  final IDateTimeProvider _dateTimeProvider;

  TripRepositoryImpl(this._supabase, this._dateTimeProvider);

  String get _orgId {
    final orgId =
        _supabase.auth.currentSession?.user.appMetadata['org_id'] as String?;
    if (orgId == null) throw StateError('No organization in session JWT');
    return orgId;
  }

  @override
  Future<List<Trip>> getTrips() async {
    try {
      final response = await _supabase
          .from('trips_audit')
          .select('*, routes(gtfs_route_id)')
          .order('start_time', ascending: false);

      return (response as List).map((data) {
        return TripMapper.fromSupabase(data as Map<String, dynamic>);
      }).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'trip');
    }
  }

  @override
  Future<Trip> startTrip(String driverId, String routeId) async {
    String realRouteUUID;

    final Map? routeRes;
    try {
      routeRes = await _supabase
          .from('routes')
          .select('id')
          .eq('gtfs_route_id', routeId)
          .maybeSingle();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'trip');
    }

    if (routeRes == null) {
      try {
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
      } on PostgrestException catch (e) {
        throw mapPostgrestToDomainException(e, resourceType: 'trip');
      }
    } else {
      realRouteUUID = routeRes['id'];
    }

    try {
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

      return TripMapper.fromSupabase(response);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'trip');
    }
  }

  @override
  Future<void> endTrip(String tripId) async {
    try {
      await _supabase
          .from('trips_audit')
          .update({
            'end_time': _dateTimeProvider.nowUtc().toIso8601String(),
            'status': 'completed',
          })
          .eq('id', tripId);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'trip');
    }
  }
}
