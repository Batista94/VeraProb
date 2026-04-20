import 'package:veraprob/domain/entities/transit_route.dart';

/// Port for transit route CRUD operations.
///
/// Concrete implementation: [PostgresTransitRouteRepository].
/// INV-18: Pure Dart interface — zero infrastructure dependencies.
abstract class ITransitRouteRepository {
  Future<List<TransitRoute>> getRoutes();
  Future<TransitRoute> addRoute({
    required String shortName,
    required String longName,
    String? color,
    String? gtfsRouteId,
  });
  Future<void> updateRoute(TransitRoute route);
  Future<void> deleteRoute(String routeId);
}
