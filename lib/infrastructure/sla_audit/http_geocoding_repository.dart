import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:veraprob/domain/sla_audit/geocoding_repository.dart';

class HttpGeocodingRepository implements GeocodingRepository {
  final http.Client _client;

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

    final response = await _client.get(
      uri,
      headers: {
        'User-Agent': 'veraprob/1.0 (admin@veraprob.app)',
        'Accept-Language': 'pt-BR,pt;q=0.9',
      },
    );

    if (response.statusCode != 200) return [];

    final json = jsonDecode(response.body) as List;
    return json
        .map(
          (e) => PlaceSuggestion(
            displayName: e['display_name'] as String,
            lat: double.parse(e['lat'] as String),
            lng: double.parse(e['lon'] as String),
          ),
        )
        .toList();
  }

  @override
  Future<String?> reverseGeocode(double lat, double lng) async {
    // Round to 4dp (~11m): caps Nominatim call volume and stabilizes caching.
    final rLat = double.parse(lat.toStringAsFixed(4));
    final rLng = double.parse(lng.toStringAsFixed(4));

    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': rLat.toString(),
      'lon': rLng.toString(),
      'format': 'json',
    });

    final response = await _client.get(
      uri,
      headers: {
        'User-Agent': 'veraprob/1.0 (admin@veraprob.app)',
        'Accept-Language': 'pt-BR,pt;q=0.9',
      },
    );

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['display_name'] as String?;
  }
}
