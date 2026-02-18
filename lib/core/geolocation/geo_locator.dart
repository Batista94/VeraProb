import 'package:geolocator/geolocator.dart';
import 'geo_locator_stub.dart'
    if (dart.library.io) 'geo_locator_mobile.dart'
    if (dart.library.html) 'geo_locator_web.dart';

abstract class GeoLocatorService {
  Stream<Position> getPositionStream();
  Future<Position> getCurrentPosition();

  factory GeoLocatorService() => getGeoLocator();
}
