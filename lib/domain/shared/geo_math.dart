import 'dart:math';

/// Pure Dart geospatial math utilities.
///
/// Consolidates the haversine formula previously duplicated across
/// [SpoofingDetector], [TelemetryIngestionPipeline],
/// [ContractualEvaluationEngine], and [OperationalStateNormalizer].
///
/// No Flutter or Supabase dependencies (INV-18).
class GeoMath {
  const GeoMath._();

  /// Haversine distance in metres between two lat/lng points.
  static double haversineMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // pi / 180
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000;
  }

  /// Implied speed in cm/s between two points given [elapsedSeconds].
  ///
  /// Returns `null` if [elapsedSeconds] is 0 (same timestamp — cannot compute).
  /// Uses integer cm/s to align with [CanonicalFact.speedCms] (INV-19 spirit).
  static int? impliedSpeedCms(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
    int elapsedSeconds,
  ) {
    if (elapsedSeconds == 0) return null;
    final distM = haversineMeters(lat1, lon1, lat2, lon2);
    return (distM / elapsedSeconds * 100).round();
  }

  /// Tests whether a line segment intersects or touches a circle.
  ///
  /// Uses a flat-earth approximation valid for distances < 5 km
  /// (geofences are typically 100–500 m).
  static bool lineIntersectsCircle(
    double lat1,
    double lng1, // segment start
    double lat2,
    double lng2, // segment end
    double centerLat,
    double centerLng,
    double radiusMeters,
  ) {
    const mPerDegLat = 111319.0;
    final mPerDegLng = 111319.0 * cos(centerLat * pi / 180.0);

    // Local metric coords relative to geofence center
    final x1 = (lng1 - centerLng) * mPerDegLng;
    final y1 = (lat1 - centerLat) * mPerDegLat;
    final x2 = (lng2 - centerLng) * mPerDegLng;
    final y2 = (lat2 - centerLat) * mPerDegLat;

    final dx = x2 - x1;
    final dy = y2 - y1;
    final lenSq = dx * dx + dy * dy;

    if (lenSq == 0.0) return (x1 * x1 + y1 * y1) <= radiusMeters * radiusMeters;

    // Project origin onto segment, clamp to [0,1]
    final t = ((-x1) * dx + (-y1) * dy) / lenSq;
    final tC = t.clamp(0.0, 1.0);
    final cx = x1 + tC * dx;
    final cy = y1 + tC * dy;

    return (cx * cx + cy * cy) <= radiusMeters * radiusMeters;
  }
}
