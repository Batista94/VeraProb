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
}
