// TDD anchor — Phase 10 Workstream 2 (MAVERICK)
// Tests the Haversine geofence logic used in telegram-webhook for GPS auto-classify.
// INV-18: GPS from EXIF only; Telegram API provides no GPS coordinates.
// smart_classify capability flag gates the whole flow (OrgCapabilities.smartClassify).

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';

// Mirrors haversineMeters() from telegram-webhook/index.ts (inline, no PostGIS)
double haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0; // Earth radius in metres
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return r * c;
}

// Mirrors suggestCategoryFromGps() logic in telegram-webhook/index.ts
String? suggestCategoryFromGps({
  required double photoLat,
  required double photoLon,
  required double? originLat,
  required double? originLon,
  required double? originRadius,
  required double? destLat,
  required double? destLon,
  required double? destRadius,
  required bool smartClassifyEnabled,
}) {
  if (!smartClassifyEnabled) return null;
  if (originLat != null && originLon != null && originRadius != null) {
    if (haversineMeters(photoLat, photoLon, originLat, originLon) <=
        originRadius) {
      return 'carregamento';
    }
  }
  if (destLat != null && destLon != null && destRadius != null) {
    if (haversineMeters(photoLat, photoLon, destLat, destLon) <= destRadius) {
      return 'lacre';
    }
  }
  return null;
}

void main() {
  // São Paulo city hall as fake origin zone
  const originLat = -23.5505;
  const originLon = -46.6333;
  const originRadius = 200.0; // 200 metres

  // Guarulhos airport as fake destination zone
  const destLat = -23.4356;
  const destLon = -46.4731;
  const destRadius = 500.0; // 500 metres

  group('Haversine distance', () {
    test('same point = 0 metres', () {
      final d = haversineMeters(originLat, originLon, originLat, originLon);
      expect(d, closeTo(0, 0.01));
    });

    test('known distance São Paulo city hall → Guarulhos airport ≈ 20.7km', () {
      final d = haversineMeters(originLat, originLon, destLat, destLon);
      expect(d, greaterThan(18000));
      expect(d, lessThan(24000));
    });
  });

  group('GPS auto-classify — origin zone (carregamento)', () {
    test('photo within origin radius → suggested = carregamento', () {
      // 50m north of origin zone centre — within 200m radius
      const photoLat = originLat + 0.00045; // ~50m north
      const photoLon = originLon;

      final result = suggestCategoryFromGps(
        photoLat: photoLat,
        photoLon: photoLon,
        originLat: originLat,
        originLon: originLon,
        originRadius: originRadius,
        destLat: destLat,
        destLon: destLon,
        destRadius: destRadius,
        smartClassifyEnabled: true,
      );
      expect(result, equals('carregamento'));
    });

    test('photo outside both zones → no suggestion', () {
      // Campinas: well outside both zones
      const photoLat = -22.9068;
      const photoLon = -47.0626;

      final result = suggestCategoryFromGps(
        photoLat: photoLat,
        photoLon: photoLon,
        originLat: originLat,
        originLon: originLon,
        originRadius: originRadius,
        destLat: destLat,
        destLon: destLon,
        destRadius: destRadius,
        smartClassifyEnabled: true,
      );
      expect(result, isNull);
    });
  });

  group('GPS auto-classify — destination zone (lacre)', () {
    test('photo within destination radius → suggested = lacre', () {
      // 100m from Guarulhos airport centre — within 500m radius
      const photoLat = destLat + 0.0009; // ~100m north
      const photoLon = destLon;

      final result = suggestCategoryFromGps(
        photoLat: photoLat,
        photoLon: photoLon,
        originLat: originLat,
        originLon: originLon,
        originRadius: originRadius,
        destLat: destLat,
        destLon: destLon,
        destRadius: destRadius,
        smartClassifyEnabled: true,
      );
      expect(result, equals('lacre'));
    });
  });

  group('GPS auto-classify — capability gate', () {
    test('smartClassify=false → no suggestion even at origin zone', () {
      final result = suggestCategoryFromGps(
        photoLat: originLat,
        photoLon: originLon,
        originLat: originLat,
        originLon: originLon,
        originRadius: originRadius,
        destLat: null,
        destLon: null,
        destRadius: null,
        smartClassifyEnabled: false, // capability disabled
      );
      expect(result, isNull);
    });

    test('null zones → no suggestion regardless of position', () {
      final result = suggestCategoryFromGps(
        photoLat: originLat,
        photoLon: originLon,
        originLat: null,
        originLon: null,
        originRadius: null,
        destLat: null,
        destLon: null,
        destRadius: null,
        smartClassifyEnabled: true,
      );
      expect(result, isNull);
    });
  });
}
