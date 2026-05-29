import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veraprob/infrastructure/sla_audit/http_geocoding_repository.dart';

void main() {
  group('HttpGeocodingRepository.reverseGeocode', () {
    test('200 response returns display_name', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient(
          (_) async => http.Response(
            '{"display_name": "Av. Paulista, 1578, São Paulo"}',
            200,
          ),
        ),
      );

      final result = await repo.reverseGeocode(-23.5613, -46.6565);

      expect(result, 'Av. Paulista, 1578, São Paulo');
    });

    test('non-200 response returns null', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient((_) async => http.Response('error', 500)),
      );

      expect(await repo.reverseGeocode(-23.5613, -46.6565), isNull);
    });

    test('200 body without display_name returns null', () async {
      final repo = HttpGeocodingRepository(
        client: MockClient((_) async => http.Response('{}', 200)),
      );

      expect(await repo.reverseGeocode(-23.5613, -46.6565), isNull);
    });

    test('rounds coordinates to 4 decimal places in the request URI', () async {
      late Uri captured;
      final repo = HttpGeocodingRepository(
        client: MockClient((req) async {
          captured = req.url;
          return http.Response('{"display_name": "x"}', 200);
        }),
      );

      await repo.reverseGeocode(-23.56131234, -46.65659876);

      expect(captured.queryParameters['lat'], '-23.5613');
      expect(captured.queryParameters['lon'], '-46.6566');
      expect(captured.queryParameters['format'], 'json');
    });
  });
}
