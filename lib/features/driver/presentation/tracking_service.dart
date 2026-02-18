import 'dart:async';
import '../../../core/geolocation/geo_locator.dart';
import '../../shared/data/repositories/vehicle_repository.dart';
import '../../shared/domain/entities/vehicle_position.dart';
import '../../shared/data/repositories/trip_repository.dart';

class TrackingService {
  final GeoLocatorService _geoLocator;
  final IVehiclePositionService _vehicleRepository;
  final ITripRepository _tripRepository;
  StreamSubscription? _positionSubscription;

  // Real database ID for the trip, not the route/line label
  String? currentTripDbId;
  String? currentRouteId;

  TrackingService(
    this._geoLocator,
    this._vehicleRepository,
    this._tripRepository,
  );

  Future<void> startTracking(String routeId, String driverId) async {
    currentRouteId = routeId;

    // Start session in DB
    final trip = await _tripRepository.startTrip(driverId, routeId);
    currentTripDbId = trip.id;

    _positionSubscription = _geoLocator.getPositionStream().listen((position) {
      if (currentTripDbId == null) return;

      final vehiclePos = VehiclePosition(
        tripId:
            currentRouteId!, // The UI expects route/line ID here, strictly speaking GTFS uses trip_id
        latitude: position.latitude,
        longitude: position.longitude,
        speed: position.speed,
        heading: position.heading,
        timestamp: DateTime.now(),
        source: 'driver_app_gps',
      );

      _vehicleRepository.sendVehiclePosition(vehiclePos);
    });
  }

  Future<void> stopTracking() async {
    _positionSubscription?.cancel();
    _positionSubscription = null;

    if (currentTripDbId != null) {
      await _tripRepository.endTrip(currentTripDbId!);
      currentTripDbId = null;
      currentRouteId = null;
    }
  }
}
