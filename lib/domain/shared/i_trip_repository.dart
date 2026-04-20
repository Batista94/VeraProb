import 'package:veraprob/domain/entities/trip.dart';

/// Domain contract for trip persistence.
///
/// Concrete implementations live in [lib/infrastructure/shared/].
abstract class ITripRepository {
  Future<Trip> startTrip(String driverId, String routeId);
  Future<void> endTrip(String tripId);
  Future<List<Trip>> getTrips();
}
