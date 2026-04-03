import 'package:veraprob/domain/entities/trip.dart';

class TripMapper {
  static Trip fromSupabase(Map<String, dynamic> data) {
    final routeCode = data['routes'] != null
        ? data['routes']['gtfs_route_id']
        : data['route_id'];

    return Trip(
      id: data['id'] as String,
      routeId: routeCode as String,
      driverId: data['driver_id'] as String,
      startTime: DateTime.parse(data['start_time'] as String),
      endTime: data['end_time'] != null
          ? DateTime.parse(data['end_time'] as String)
          : null,
      status: data['status'] as String,
    );
  }

  // toSupabase is handled by repository logic (startTrip/endTrip)
  // as it involves complex route UUID lookups and status updates.
}
