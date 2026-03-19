import 'package:veraprob/domain/entities/transit_route.dart';

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
