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

  @override
  Future<List<TransitRoute>> getRoutes() {
    return withErrorHandler('transit_route', null, () async {
      final response = await client
          .from('routes')
          .select()
          .order('short_name', ascending: true);
      return (response as List)
          .map((row) => TransitRoute.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<TransitRoute> addRoute({
    required String shortName,
    required String longName,
    String? color,
    String? gtfsRouteId,
  }) {
    return withErrorHandler('transit_route', null, () async {
      final response = await client
          .from('routes')
          .insert({
            'organization_id': sessionOrgId,
            'short_name': shortName.trim(),
            'long_name': longName.trim(),
            'color': color?.trim(),
            'gtfs_route_id': gtfsRouteId?.trim(),
          })
          .select()
          .single();
      return TransitRoute.fromJson(response);
    });
  }

  @override
  Future<void> updateRoute(TransitRoute route) {
    return withErrorHandler(
      'transit_route',
      route.id,
      () => client
          .from('routes')
          .update({
            'short_name': route.shortName.trim(),
            'long_name': route.longName.trim(),
            'color': route.color?.trim(),
            'gtfs_route_id': route.gtfsRouteId?.trim(),
          })
          .eq('id', route.id),
    );
  }

  @override
  Future<void> deleteRoute(String routeId) {
    return withErrorHandler(
      'transit_route',
      routeId,
      () => client.from('routes').delete().eq('id', routeId),
    );
  }
}
