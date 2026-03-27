import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/core/utils/geo_math.dart';

void main() {
  group('GeoMath.haversineMeters', () {
    test('returns 0 for same point', () {
      final d = GeoMath.haversineMeters(-23.5505, -46.6333, -23.5505, -46.6333);
      expect(d, equals(0.0));
    });

    test('computes São Paulo to Rio de Janeiro ≈ 357 km', () {
      // SP: -23.5505, -46.6333 / RJ: -22.9068, -43.1729
      final d = GeoMath.haversineMeters(-23.5505, -46.6333, -22.9068, -43.1729);
      expect(d, closeTo(357000, 5000)); // ±5 km tolerance
    });

    test('computes short distance (~111 m for 0.001 degree at equator)', () {
      final d = GeoMath.haversineMeters(0.0, 0.0, 0.001, 0.0);
      expect(d, closeTo(111.2, 1.0)); // ~111.2 m per 0.001°
    });

    test('is symmetric', () {
      final d1 = GeoMath.haversineMeters(
        -23.5505,
        -46.6333,
        -22.9068,
        -43.1729,
      );
      final d2 = GeoMath.haversineMeters(
        -22.9068,
        -43.1729,
        -23.5505,
        -46.6333,
      );
      expect(d1, equals(d2));
    });
  });

  group('GeoMath.impliedSpeedCms', () {
    test('returns null when elapsedSeconds is 0', () {
      final speed = GeoMath.impliedSpeedCms(0.0, 0.0, 0.001, 0.0, 0);
      expect(speed, isNull);
    });

    test('computes correct speed for known distance and time', () {
      // 111.2 m in 10 seconds = 11.12 m/s = 1112 cm/s
      final speed = GeoMath.impliedSpeedCms(0.0, 0.0, 0.001, 0.0, 10);
      expect(speed, closeTo(1112, 10)); // ±10 cm/s tolerance
    });

    test('returns 0 for same point with positive elapsed time', () {
      final speed = GeoMath.impliedSpeedCms(0.0, 0.0, 0.0, 0.0, 60);
      expect(speed, equals(0));
    });

    test('200 km/h scenario returns ~5556 cm/s', () {
      // 200 km/h = 55.556 m/s = 5555.6 cm/s
      // Need to find lat/lng that gives ~55.556 m distance in 1 second
      // 55.556 m ≈ 0.0005° at equator
      final speed = GeoMath.impliedSpeedCms(0.0, 0.0, 0.0005, 0.0, 1);
      // ~55.6 m / 1 s = 5560 cm/s
      expect(speed, closeTo(5560, 50));
    });
  });
}
