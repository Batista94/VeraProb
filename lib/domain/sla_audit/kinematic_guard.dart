import 'package:veraprob/domain/shared/geo_math.dart';
import 'canonical_fact.dart';
import 'kinematic_validation_result.dart';

/// Pure domain service that validates the physical plausibility of
/// consecutive [CanonicalFact] events for the same asset.
///
/// Implements INV-17 (Kinematic Guard) at the domain layer.
/// The database trigger is the authoritative enforcement layer;
/// this service enables TDD and client-side pre-filtering.
///
/// **Formula:** `v = Δd / Δt` where `Δd` is haversine distance
/// and `Δt` is the difference in [CanonicalFact.gpsTimestamp] (INV-10).
///
/// No Flutter or Supabase dependencies (INV-18).
class KinematicGuard {
  /// Default: 200 km/h = 5556 cm/s (passenger/commercial vehicle).
  static const int defaultMaxSpeedCms = 5556;

  /// Minimum distance in metres to consider a same-timestamp jump anomalous.
  static const double sameTimestampJumpThresholdM =
      5.0; // Physical Metric - Double Required

  final int maxSpeedCms;

  const KinematicGuard({this.maxSpeedCms = defaultMaxSpeedCms});

  /// Validates the transition from [previous] to [current].
  ///
  /// Both facts must belong to the same `(organizationId, assetId)` pair.
  /// Uses [CanonicalFact.gpsTimestamp] for temporal delta (INV-10).
  KinematicValidationResult validate(
    CanonicalFact previous,
    CanonicalFact current,
  ) {
    final elapsedSeconds = current.gpsTimestamp
        .difference(previous.gpsTimestamp)
        .inSeconds
        .abs();

    final distM = GeoMath.haversineMeters(
      previous.lat,
      previous.lng,
      current.lat,
      current.lng,
    );

    // Same timestamp: can't compute speed, but flag large position jumps.
    if (elapsedSeconds == 0) {
      if (distM > sameTimestampJumpThresholdM) {
        return KinematicValidationResult.violation(
          type: KinematicViolationType.sameTimestampPositionJump,
          distanceMeters: distM,
          elapsedSeconds: 0,
          impliedSpeedCms: null,
          maxAllowedSpeedCms: maxSpeedCms,
        );
      }
      return KinematicValidationResult.ok(
        distanceMeters: distM,
        elapsedSeconds: 0,
        impliedSpeedCms: null,
        maxAllowedSpeedCms: maxSpeedCms,
      );
    }

    final impliedCms = GeoMath.impliedSpeedCms(
      previous.lat,
      previous.lng,
      current.lat,
      current.lng,
      elapsedSeconds,
    )!;

    if (impliedCms > maxSpeedCms) {
      return KinematicValidationResult.violation(
        type: KinematicViolationType.impossibleSpeed,
        distanceMeters: distM,
        elapsedSeconds: elapsedSeconds,
        impliedSpeedCms: impliedCms,
        maxAllowedSpeedCms: maxSpeedCms,
      );
    }

    return KinematicValidationResult.ok(
      distanceMeters: distM,
      elapsedSeconds: elapsedSeconds,
      impliedSpeedCms: impliedCms,
      maxAllowedSpeedCms: maxSpeedCms,
    );
  }
}
