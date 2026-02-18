import 'package:geolocator/geolocator.dart';
import 'geo_locator.dart';

class MobileGeoLocator implements GeoLocatorService {
  @override
  Stream<Position> getPositionStream() {
    return Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  @override
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition();
  }
}

GeoLocatorService getGeoLocator() => MobileGeoLocator();
