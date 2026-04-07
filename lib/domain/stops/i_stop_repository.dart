import 'package:veraprob/domain/entities/stop.dart';

/// Repository contract for querying operational service points (stops).
///
/// Transport-agnostic: works for bus stops, freight checkpoints, or any
/// geo-anchored service waypoint. Implementations live in infrastructure.
abstract class IStopRepository {
  /// Returns stops within a reasonable radius of [lat]/[lon].
  /// Coordinates are WGS-84 decimal degrees.
  Future<List<Stop>> getNearbyStops(
    double lat,
    double lon,
  ); // Physical Metric - Double Required
}
