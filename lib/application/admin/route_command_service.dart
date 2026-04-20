import 'package:veraprob/domain/assets/i_transit_route_repository.dart';
import 'package:veraprob/domain/entities/transit_route.dart';

/// Port for route lifecycle mutations.
///
/// Concrete implementation: [RouteCommandServiceImpl].
abstract class RouteCommandService {
  Future<TransitRoute> addRoute({
    required String shortName,
    required String longName,
    String? color,
  });

  Future<void> deleteRoute(String id);
}

/// In-memory-friendly implementation backed by [ITransitRouteRepository].
class RouteCommandServiceImpl implements RouteCommandService {
  final ITransitRouteRepository _repository;

  RouteCommandServiceImpl(this._repository);

  @override
  Future<TransitRoute> addRoute({
    required String shortName,
    required String longName,
    String? color,
  }) async {
    return _repository.addRoute(
      shortName: shortName.trim(),
      longName: longName.trim(),
      color: color?.trim(),
    );
  }

  @override
  Future<void> deleteRoute(String id) async {
    await _repository.deleteRoute(id);
  }
}
