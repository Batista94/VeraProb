import 'package:geolocator/geolocator.dart';
import 'geo_locator.dart';

class WebGeoLocator implements GeoLocatorService {
  @override
  Stream<Position> getPositionStream() {
    // Web implementation relies on browser geolocator support
    return Geolocator.getPositionStream();
  }

  @override
  Future<Position> getCurrentPosition() {
    return Geolocator.getCurrentPosition();
  }
}

GeoLocatorService getGeoLocator() => WebGeoLocator();
