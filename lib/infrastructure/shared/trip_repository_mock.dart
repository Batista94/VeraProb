import 'package:veraprob/domain/shared/i_trip_repository.dart';
import 'package:veraprob/domain/entities/trip.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';

/// In-memory mock of [ITripRepository] for tests and offline mode.
class TripRepositoryMock implements ITripRepository {
  final List<Trip> _trips = [];
  final IDateTimeProvider _dateTimeProvider;

  TripRepositoryMock(this._dateTimeProvider);

  @override
  Future<Trip> startTrip(String driverId, String routeId) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final trip = Trip(
      id: _dateTimeProvider.nowUtc().millisecondsSinceEpoch.toString(),
      driverId: driverId,
      routeId: routeId,
      startTime: _dateTimeProvider.nowUtc(),
      status: 'active',
    );
    _trips.add(trip);
    return trip;
  }

  @override
  Future<void> endTrip(String tripId) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final index = _trips.indexWhere((t) => t.id == tripId);
    if (index != -1) {
      _trips[index] = _trips[index].copyWith(
        endTime: _dateTimeProvider.nowUtc(),
        status: 'completed',
      );
    }
  }

  @override
  Future<List<Trip>> getTrips() async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    return List.from(_trips);
  }
}
