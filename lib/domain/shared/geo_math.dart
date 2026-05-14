import 'dart:math';

/// Pure Dart geospatial math utilities.
///
/// Consolidates the haversine formula previously duplicated across
/// [SpoofingDetector], [TelemetryIngestionPipeline],
/// [ContractualEvaluationEngine], and [OperationalStateNormalizer].
///
/// No Flutter or Supabase dependencies (INV-18).
///
/// **INV-12:** All [double] parameters represent physical geographic
/// coordinates (degrees) or spatial distances (metres) — not monetary values.
/// Annotated with `// Physical Metric - Double Required` per INV-12.
class GeoMath {
  const GeoMath._();

  /// Haversine distance in metres between two lat/lng points.
  ///
  /// Coordinates are WGS-84 decimal degrees. Returns a physical distance
  /// in metres as [double] — a spatial quantity, not a financial value (INV-12).
  static double haversineMeters(
    double lat1, // Physical Metric - Double Required
    double lon1, // Physical Metric - Double Required
    double lat2, // Physical Metric - Double Required
    double lon2, // Physical Metric - Double Required
  ) {
    const p =
        0.017453292519943295; // pi / 180  // Physical Metric - Double Required
    final a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)) * 1000; // Physical Metric - Double Required
  }

  /// Implied speed in cm/s between two points given [elapsedSeconds].
  ///
  /// Returns `null` if [elapsedSeconds] is 0 (same timestamp — cannot compute).
  /// Uses integer cm/s to align with [CanonicalFact.speedCms] (INV-4 / INV-19 spirit).
  static int? impliedSpeedCms(
    double lat1, // Physical Metric - Double Required
    double lon1, // Physical Metric - Double Required
    double lat2, // Physical Metric - Double Required
    double lon2, // Physical Metric - Double Required
    int elapsedSeconds,
  ) {
    if (elapsedSeconds == 0) return null;
    final distM = haversineMeters(
      lat1,
      lon1,
      lat2,
      lon2,
    ); // Physical Metric - Double Required
    return (distM / elapsedSeconds * 100).round();
  }

  /// Tests whether a line segment intersects or touches a circle.
  ///
  /// Uses a flat-earth approximation valid for distances < 5 km
  /// (geofences are typically 100–500 m).
  static bool lineIntersectsCircle(
    double lat1, // Physical Metric - Double Required
    double lng1, // segment start  // Physical Metric - Double Required
    double lat2, // Physical Metric - Double Required
    double lng2, // segment end  // Physical Metric - Double Required
    double centerLat, // Physical Metric - Double Required
    double centerLng, // Physical Metric - Double Required
    double radiusMeters, // Physical Metric - Double Required
  ) {
    const mPerDegLat = 111319.0; // Physical Metric - Double Required
    final mPerDegLng =
        111319.0 *
        cos(centerLat * pi / 180.0); // Physical Metric - Double Required

    // Local metric coords relative to geofence center
    final x1 =
        (lng1 - centerLng) * mPerDegLng; // Physical Metric - Double Required
    final y1 =
        (lat1 - centerLat) * mPerDegLat; // Physical Metric - Double Required
    final x2 =
        (lng2 - centerLng) * mPerDegLng; // Physical Metric - Double Required
    final y2 =
        (lat2 - centerLat) * mPerDegLat; // Physical Metric - Double Required

    final dx = x2 - x1; // Physical Metric - Double Required
    final dy = y2 - y1; // Physical Metric - Double Required
    final lenSq = dx * dx + dy * dy; // Physical Metric - Double Required

    if (lenSq == 0.0) {
      return (x1 * x1 + y1 * y1) <=
          radiusMeters * radiusMeters; // Physical Metric - Double Required
    }

    // Project origin onto segment, clamp to [0,1]
    final t =
        ((-x1) * dx + (-y1) * dy) / lenSq; // Physical Metric - Double Required
    final tC = t.clamp(0.0, 1.0); // Physical Metric - Double Required
    final cx = x1 + tC * dx; // Physical Metric - Double Required
    final cy = y1 + tC * dy; // Physical Metric - Double Required

    return (cx * cx + cy * cy) <=
        radiusMeters * radiusMeters; // Physical Metric - Double Required
  }
}
