import '../../domain/entities/trip.dart';

abstract class ITripRepository {
  Future<Trip> startTrip(String driverId, String routeId);
  Future<void> endTrip(String tripId);
  Future<List<Trip>> getTrips();
}

class TripRepositoryMock implements ITripRepository {
  final List<Trip> _trips = [];

  @override
  Future<Trip> startTrip(String driverId, String routeId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final trip = Trip(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
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
    // Return a copy to avoid external modification issues
    return List.from(_trips);
  }
}
