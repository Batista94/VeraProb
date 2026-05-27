// Unit tests for MapTilerStaticMapService.
//
// Uses MockClient to avoid real HTTP calls.
// Covers INV-12 (Physical Metric — lat/lng as double) and
// PdfGenerationException surface for non-200 responses and network errors.

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:veraprob/domain/reporting/i_forensic_pdf_generator.dart';
import 'package:veraprob/infrastructure/reporting/maptiler_static_map_service.dart';

void main() {
  group('MapTilerStaticMapService', () {
    // ── Happy Path ────────────────────────────────────────────────────────────

    test('getStaticMap returns response body bytes on HTTP 200', () async {
      final expectedBytes = [0x89, 0x50, 0x4E, 0x47]; // PNG magic
      final client = MockClient((_) async {
        return http.Response.bytes(expectedBytes, 200);
      });

      final service = MapTilerStaticMapService(httpClient: client);
      final result = await service.getStaticMap(
        lat: -23.550520, // Physical Metric - Double Required
        lng: -46.633309, // Physical Metric - Double Required
        zoom: 14,
      );

      expect(result, equals(expectedBytes));
    });

    test(
      'getStaticMap builds URL with correct coordinate order (lng,lat — MapTiler spec)',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response.bytes([1, 2, 3], 200);
        });

        final service = MapTilerStaticMapService(httpClient: client);
        // Physical Metric - Double Required
        await service.getStaticMap(lat: -23.5505, lng: -46.6333, zoom: 12);

        expect(captured, isNotNull);
        final url = captured!.url.toString();
        // MapTiler Static Maps API: {lng},{lat},{zoom}
        expect(url, contains('-46.6333,-23.5505,12'));
      },
    );

    // ── Error Handling ────────────────────────────────────────────────────────

    test('getStaticMap throws PdfGenerationException on HTTP 404', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      final service = MapTilerStaticMapService(httpClient: client);

      await expectLater(
        service.getStaticMap(lat: 0.0, lng: 0.0, zoom: 10),
        throwsA(
          isA<PdfGenerationException>().having(
            (e) => e.message,
            'message',
            contains('404'),
          ),
        ),
      );
    });

    test('getStaticMap throws PdfGenerationException on HTTP 401', () async {
      final client = MockClient(
        (_) async => http.Response('Unauthorized', 401),
      );
      final service = MapTilerStaticMapService(httpClient: client);

      await expectLater(
        service.getStaticMap(lat: 0.0, lng: 0.0, zoom: 10),
        throwsA(isA<PdfGenerationException>()),
      );
    });

    test(
      'getStaticMap throws PdfGenerationException on network error',
      () async {
        final client = MockClient(
          (_) async => throw Exception('Network timeout'),
        );
        final service = MapTilerStaticMapService(httpClient: client);

        await expectLater(
          service.getStaticMap(lat: 0.0, lng: 0.0, zoom: 10),
          throwsA(isA<PdfGenerationException>()),
        );
      },
    );

    // ── Precision Guard (INV-12) ──────────────────────────────────────────────

    test(
      'getStaticMap preserves full double precision in URL (INV-12)',
      () async {
        http.Request? captured;
        final client = MockClient((request) async {
          captured = request;
          return http.Response.bytes([1], 200);
        });

        final service = MapTilerStaticMapService(httpClient: client);
        // Use coordinates requiring >6 decimal places of precision.
        // Physical Metric - Double Required
        await service.getStaticMap(
          lat: -23.5505201234,
          lng: -46.6333099876,
          zoom: 16,
        );

        final url = captured!.url.toString();
        // Full precision must be preserved — no rounding to integer.
        expect(url, isNot(contains(',-23,')));
        expect(url, isNot(contains(',-46,')));
      },
    );
  });
}
