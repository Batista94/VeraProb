import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:veraprob/domain/sla_audit/geocoding_repository.dart';
import 'package:veraprob/infrastructure/observability/logger_service.dart';

class HttpGeocodingRepository implements GeocodingRepository {
  final http.Client _client;
  final LoggerService _logger = LoggerService();

  HttpGeocodingRepository({http.Client? client})
    : _client = client ?? http.Client();

  @override
  Future<List<PlaceSuggestion>> search(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '5',
      'countrycodes': 'br',
      'addressdetails': '0',
    });

    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'veraprob/1.0 (admin@veraprob.app)',
          'Accept-Language': 'pt-BR,pt;q=0.9',
        },
      );

      if (response.statusCode != 200) {
        _logger.log(
          'Nominatim search failed with status: ${response.statusCode}',
          component: 'HttpGeocodingRepository',
        );
        return [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        _logger.log(
          'Nominatim search returned unexpected JSON structure',
          component: 'HttpGeocodingRepository',
        );
        return [];
      }

      final results = <PlaceSuggestion>[];
      for (final item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        final displayName = item['display_name'];
        final latStr = item['lat'];
        final lonStr = item['lon'];

        if (displayName is! String || latStr is! String || lonStr is! String) {
          continue;
        }

        final parsedLat = double.tryParse(
          latStr,
        ); // Physical Metric - Double Required
        final parsedLng = double.tryParse(
          lonStr,
        ); // Physical Metric - Double Required
        if (parsedLat == null || parsedLng == null) continue;

        results.add(
          PlaceSuggestion(
            displayName: displayName,
            lat: parsedLat,
            lng: parsedLng,
          ),
        );
      }
      return results;
    } catch (e, s) {
      _logger.error('Nominatim search request failed', error: e, stackTrace: s);
      return [];
    }
  }

  @override
  Future<String?> reverseGeocode(double lat, double lng) async {
    // Validate physical coordinate boundaries
    if (lat < -90.0 || lat > 90.0 || lng < -180.0 || lng > 180.0) {
      _logger.log(
        'Out-of-bounds coordinates skipped: ($lat, $lng)',
        component: 'HttpGeocodingRepository',
      );
      return null;
    }

    // Round to 4dp (~11m): caps Nominatim call volume and stabilizes caching.
    final double rLat = double.parse(
      lat.toStringAsFixed(4),
    ); // Physical Metric - Double Required
    final double rLng = double.parse(
      lng.toStringAsFixed(4),
    ); // Physical Metric - Double Required

    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': rLat.toString(),
      'lon': rLng.toString(),
      'format': 'json',
    });

    try {
      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': 'veraprob/1.0 (admin@veraprob.app)',
          'Accept-Language': 'pt-BR,pt;q=0.9',
        },
      );

      if (response.statusCode != 200) {
        _logger.log(
          'Nominatim reverse geocode failed with status: ${response.statusCode}',
          component: 'HttpGeocodingRepository',
        );
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        _logger.log(
          'Nominatim reverse geocode returned unexpected JSON structure',
          component: 'HttpGeocodingRepository',
        );
        return null;
      }

      final displayName = decoded['display_name'];
      if (displayName is! String) {
        return null;
      }
      return displayName;
    } catch (e, s) {
      _logger.error(
        'Nominatim reverse geocode request failed',
        error: e,
        stackTrace: s,
      );
      return null;
    }
  }
}
