import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/entities/transit_route.dart';
import 'package:veraprob/domain/assets/i_transit_route_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase implementation of [ITransitRouteRepository].
///
/// Wraps `SupabaseClient` so that no Widget ever imports
/// `supabase_flutter` directly (SRP-UI-LEAK prevention).
class PostgresTransitRouteRepository extends BasePostgresRepository
    implements ITransitRouteRepository {
  PostgresTransitRouteRepository(super.client);

  String get _orgId {
    final orgId =
        client.auth.currentSession?.user.appMetadata['org_id'] as String?;
    if (orgId == null) throw StateError('No organization in session JWT');
    return orgId;
  }

  @override
  Future<List<TransitRoute>> getRoutes() async {
    try {
      final response = await client
          .from('routes')
          .select()
          .order('short_name', ascending: true);
      return (response as List)
          .map((row) => TransitRoute.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'transit_route');
    }
  }

  @override
  Future<TransitRoute> addRoute({
    required String shortName,
    required String longName,
    String? color,
    String? gtfsRouteId,
  }) async {
    try {
      final response = await client
          .from('routes')
          .insert({
            'organization_id': _orgId,
            'short_name': shortName.trim(),
            'long_name': longName.trim(),
            'color': color?.trim(),
            'gtfs_route_id': gtfsRouteId?.trim(),
          })
          .select()
          .single();
      return TransitRoute.fromJson(response);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'transit_route');
    }
  }

  @override
  Future<void> updateRoute(TransitRoute route) async {
    try {
      await client
          .from('routes')
          .update({
            'short_name': route.shortName.trim(),
            'long_name': route.longName.trim(),
            'color': route.color?.trim(),
            'gtfs_route_id': route.gtfsRouteId?.trim(),
          })
          .eq('id', route.id);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'transit_route');
    }
  }

  @override
  Future<void> deleteRoute(String routeId) async {
    try {
      await client.from('routes').delete().eq('id', routeId);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'transit_route');
    }
  }
}
