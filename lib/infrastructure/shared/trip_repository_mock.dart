import 'package:veraprob/domain/shared/i_trip_repository.dart';
import 'package:veraprob/domain/entities/trip.dart';

/// In-memory mock of [ITripRepository] for tests and offline mode.
class TripRepositoryMock implements ITripRepository {
  final List<Trip> _trips = [];

  @override
  Future<Trip> startTrip(String driverId, String routeId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final trip = Trip(
      id: DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
      driverId: driverId,
      routeId: routeId,
      startTime: DateTime.now().toUtc(),
      status: 'active',
    );
    _trips.add(trip);
    return trip;
  }

  @override
  Future<void> endTrip(String tripId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index != -1) {
      _trips[index] = _trips[index].copyWith(
        endTime: DateTime.now().toUtc(),
        status: 'completed',
      );
    }
  }

  @override
  Future<List<Trip>> getTrips() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return List.from(_trips);
  }
}
