// Contract tests for IStaticMapService.
//
// Validates port contract using a fake implementation.
// Covers INV-12 (lat/lng as double — Physical Metric) and
// the exception surface guaranteed by the interface.

import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/reporting/i_forensic_pdf_generator.dart';
import 'package:veraprob/domain/reporting/i_static_map_service.dart';

// ── Fake ──────────────────────────────────────────────────────────────────────

class _RecordingStaticMapService implements IStaticMapService {
  final List<({num lat, num lng, int zoom})> calls = [];
  final bool shouldThrow;

  _RecordingStaticMapService({this.shouldThrow = false});

  @override
  Future<List<int>> getStaticMap({
    required num lat,
    required num lng,
    required int zoom,
  }) async {
    if (shouldThrow) {
      throw const PdfGenerationException('Fake map API failure');
    }
    calls.add((lat: lat, lng: lng, zoom: zoom));
    // Minimal PNG magic bytes so callers can detect format.
    return [0x89, 0x50, 0x4E, 0x47]; // .PNG
  }
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('IStaticMapService — Contract', () {
    test('getStaticMap returns non-empty bytes on success', () async {
      final service = _RecordingStaticMapService();

      final bytes = await service.getStaticMap(
        lat: -23.550520,
        lng: -46.633309,
        zoom: 14,
      );

      expect(bytes, isNotEmpty);
    });

    test(
      'getStaticMap passes lat, lng, zoom unmodified (INV-12 — Physical Metric)',
      () async {
        final service = _RecordingStaticMapService();
        // Use high-precision doubles — must not be rounded or truncated.
        const lat = -23.550520123456789; // Physical Metric - Double Required
        const lng = -46.633309987654321; // Physical Metric - Double Required
        const zoom = 14;

        await service.getStaticMap(lat: lat, lng: lng, zoom: zoom);

        expect(service.calls.length, equals(1));
        expect(service.calls.first.lat, equals(lat));
        expect(service.calls.first.lng, equals(lng));
        expect(service.calls.first.zoom, equals(zoom));
      },
    );

    test('getStaticMap propagates PdfGenerationException on failure', () async {
      final service = _RecordingStaticMapService(shouldThrow: true);

      await expectLater(
        service.getStaticMap(lat: 0, lng: 0, zoom: 10),
        throwsA(isA<PdfGenerationException>()),
      );
    });

    test('getStaticMap accepts integer-compatible num for lat/lng', () async {
      // lat/lng typed as `num` — must accept both int and double.
      final service = _RecordingStaticMapService();

      final bytes = await service.getStaticMap(lat: -23, lng: -46, zoom: 10);

      expect(bytes, isNotEmpty);
    });

    test('different zoom levels are forwarded correctly', () async {
      final service = _RecordingStaticMapService();

      for (final zoom in [8, 12, 16, 18]) {
        await service.getStaticMap(lat: -23.55, lng: -46.63, zoom: zoom);
      }

      final zooms = service.calls.map((c) => c.zoom).toList();
      expect(zooms, containsAllInOrder([8, 12, 16, 18]));
    });
  });
}
