import 'geo_locator.dart';

// This function throws an error if neither mobile nor web implementation is loaded
GeoLocatorService getGeoLocator() =>
    throw UnsupportedError('Cannot create a GeoLocatorService');
