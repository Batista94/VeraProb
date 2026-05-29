import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veraprob/infrastructure/sla_audit/http_geocoding_repository.dart';

void main() {
  group('HttpGeocodingRepository.search', () {
    test('200 response with valid JSON returns PlaceSuggestions', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient((req) async {
          return http.Response('''[
              {"display_name": "Av. Paulista, São Paulo", "lat": "-23.5613", "lon": "-46.6565"},
              {"display_name": "Rua Augusta, São Paulo", "lat": "-23.5598", "lon": "-46.6580"}
            ]''', 200);
        }),
      );

      final results = await repo.search('Paulista');

      expect(results.length, 2);
      expect(results[0].displayName, 'Av. Paulista, São Paulo');
      // Assert double coordinates match and use INV-12 annotations
      const double expectedLat1 = -23.5613; // Physical Metric - Double Required
      const double expectedLng1 = -46.6565; // Physical Metric - Double Required
      expect(results[0].lat, expectedLat1);
      expect(results[0].lng, expectedLng1);

      expect(results[1].displayName, 'Rua Augusta, São Paulo');
      const double expectedLat2 = -23.5598; // Physical Metric - Double Required
      const double expectedLng2 = -46.6580; // Physical Metric - Double Required
      expect(results[1].lat, expectedLat2);
      expect(results[1].lng, expectedLng2);
    });

    test('200 response with empty array returns empty list', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient((req) async => http.Response('[]', 200)),
      );

      final results = await repo.search('Paulista');
      expect(results, isEmpty);
    });

    test(
      '200 response with invalid JSON structure returns empty list gracefully',
      () async {
        final repo = HttpGeocodingRepository(
          client: MockClient(
            (req) async => http.Response('{"error": "not a list"}', 200),
          ),
        );

        final results = await repo.search('Paulista');
        expect(results, isEmpty);
      },
    );

    test('200 response with missing fields skips invalid entries', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient((req) async {
          return http.Response('''[
              {"lat": "-23.5613", "lon": "-46.6565"},
              {"display_name": "Valid Place", "lat": "-23.5598", "lon": "-46.6580"},
              {"display_name": "Missing Lon", "lat": "-23.5598"}
            ]''', 200);
        }),
      );

      final results = await repo.search('Paulista');

      expect(results.length, 1);
      expect(results[0].displayName, 'Valid Place');
      const double expectedLat = -23.5598; // Physical Metric - Double Required
      const double expectedLng = -46.6580; // Physical Metric - Double Required
      expect(results[0].lat, expectedLat);
      expect(results[0].lng, expectedLng);
    });

    test(
      '200 response with invalid numeric formats skips invalid entries',
      () async {
        final repo = HttpGeocodingRepository(
          client: MockClient((req) async {
            return http.Response('''[
              {"display_name": "Invalid Lat", "lat": "abc", "lon": "-46.6565"},
              {"display_name": "Valid Place", "lat": "-23.5598", "lon": "-46.6580"}
            ]''', 200);
          }),
        );

        final results = await repo.search('Paulista');

        expect(results.length, 1);
        expect(results[0].displayName, 'Valid Place');
      },
    );

    test('non-200 responses return empty list', () async {
      for (final int code in [400, 403, 404, 429, 500]) {
        final repo = HttpGeocodingRepository(
          client: MockClient((req) async => http.Response('error', code)),
        );

        final results = await repo.search('Paulista');
        expect(
          results,
          isEmpty,
          reason: 'Should return empty for status code $code',
        );
      }
    });

    test(
      'network exception during search returns empty list gracefully',
      () async {
        final repo = HttpGeocodingRepository(
          client: MockClient(
            (req) async => throw const SocketException('No Internet'),
          ),
        );

        final results = await repo.search('Paulista');
        expect(results, isEmpty);
      },
    );

    test(
      'search request does not leak credentials or tenant headers',
      () async {
        late Map<String, String> headers;
        final repo = HttpGeocodingRepository(
          client: MockClient((req) async {
            headers = req.headers;
            return http.Response('[]', 200);
          }),
        );

        await repo.search('Paulista');

        expect(headers['User-Agent'], 'veraprob/1.0 (admin@veraprob.app)');
        expect(headers['Accept-Language'], 'pt-BR,pt;q=0.9');
        expect(headers.containsKey('Authorization'), isFalse);
        expect(headers.containsKey('cookie'), isFalse);
        expect(headers.containsKey('x-organization-id'), isFalse);
      },
    );
  });

  group('HttpGeocodingRepository.reverseGeocode', () {
    test('200 response with valid JSON returns address', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient((req) async {
          return http.Response(
            '{"display_name": "Av. Paulista, 1578, São Paulo"}',
            200,
          );
        }),
      );

      const double testLat = -23.5613; // Physical Metric - Double Required
      const double testLng = -46.6565; // Physical Metric - Double Required
      final result = await repo.reverseGeocode(testLat, testLng);

      expect(result, 'Av. Paulista, 1578, São Paulo');
    });

    test('coordinate boundary validation checks', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient((req) async => fail('Should not reach HTTP client')),
      );

      // Verify out-of-bounds latitude values fail fast and return null
      const double badLatUpper = 90.1; // Physical Metric - Double Required
      const double badLatLower = -90.1; // Physical Metric - Double Required
      const double goodLng = 0.0; // Physical Metric - Double Required

      expect(await repo.reverseGeocode(badLatUpper, goodLng), isNull);
      expect(await repo.reverseGeocode(badLatLower, goodLng), isNull);

      // Verify out-of-bounds longitude values fail fast and return null
      const double goodLat = 0.0; // Physical Metric - Double Required
      const double badLngUpper = 180.1; // Physical Metric - Double Required
      const double badLngLower = -181.0; // Physical Metric - Double Required

      expect(await repo.reverseGeocode(goodLat, badLngUpper), isNull);
      expect(await repo.reverseGeocode(goodLat, badLngLower), isNull);
    });

    test('coordinate rounding edge cases are formatted to 4dp', () async {
      late Uri capturedUri;
      final repo = HttpGeocodingRepository(
        client: MockClient((req) async {
          capturedUri = req.url;
          return http.Response('{"display_name": "x"}', 200);
        }),
      );

      // Check rounding values and verify INV-12 annotations
      const double lat1 = -23.56131234; // Physical Metric - Double Required
      const double lng1 = -46.65659876; // Physical Metric - Double Required
      await repo.reverseGeocode(lat1, lng1);
      expect(capturedUri.queryParameters['lat'], '-23.5613');
      expect(capturedUri.queryParameters['lon'], '-46.6566'); // Rounded up

      const double lat2 = -23.56135; // Physical Metric - Double Required
      const double lng2 = -46.65654; // Physical Metric - Double Required
      await repo.reverseGeocode(lat2, lng2);
      expect(capturedUri.queryParameters['lat'], '-23.5614'); // Rounds up
      expect(capturedUri.queryParameters['lon'], '-46.6565'); // Rounds down
    });

    test(
      '200 response with invalid JSON structure returns null gracefully',
      () async {
        final repo = HttpGeocodingRepository(
          client: MockClient((req) async => http.Response('[]', 200)),
        );

        const double testLat = -23.5613; // Physical Metric - Double Required
        const double testLng = -46.6565; // Physical Metric - Double Required
        final result = await repo.reverseGeocode(testLat, testLng);
        expect(result, isNull);
      },
    );

    test('200 response missing display_name returns null', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient(
          (req) async => http.Response('{"lat": "-23.5"}', 200),
        ),
      );

      const double testLat = -23.5613; // Physical Metric - Double Required
      const double testLng = -46.6565; // Physical Metric - Double Required
      final result = await repo.reverseGeocode(testLat, testLng);
      expect(result, isNull);
    });

    test('non-200 responses return null', () async {
      for (final int code in [400, 403, 404, 429, 500]) {
        final repo = HttpGeocodingRepository(
          client: MockClient((req) async => http.Response('error', code)),
        );

        const double testLat = -23.5613; // Physical Metric - Double Required
        const double testLng = -46.6565; // Physical Metric - Double Required
        final result = await repo.reverseGeocode(testLat, testLng);
        expect(
          result,
          isNull,
          reason: 'Should return null for status code $code',
        );
      }
    });

    test(
      'network exception during reverse geocode returns null gracefully',
      () async {
        final repo = HttpGeocodingRepository(
          client: MockClient(
            (req) async => throw const SocketException('No Internet'),
          ),
        );

        const double testLat = -23.5613; // Physical Metric - Double Required
        const double testLng = -46.6565; // Physical Metric - Double Required
        final result = await repo.reverseGeocode(testLat, testLng);
        expect(result, isNull);
      },
    );

    test(
      'reverseGeocode request does not leak credentials or tenant headers',
      () async {
        late Map<String, String> headers;
        final repo = HttpGeocodingRepository(
          client: MockClient((req) async {
            headers = req.headers;
            return http.Response('{"display_name": "x"}', 200);
          }),
        );

        const double testLat = -23.5613; // Physical Metric - Double Required
        const double testLng = -46.6565; // Physical Metric - Double Required
        await repo.reverseGeocode(testLat, testLng);

        expect(headers['User-Agent'], 'veraprob/1.0 (admin@veraprob.app)');
        expect(headers['Accept-Language'], 'pt-BR,pt;q=0.9');
        expect(headers.containsKey('Authorization'), isFalse);
        expect(headers.containsKey('cookie'), isFalse);
        expect(headers.containsKey('x-organization-id'), isFalse);
      },
    );
  });
}
