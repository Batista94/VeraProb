import 'package:equatable/equatable.dart';

/// Type of kinematic violation detected.
enum KinematicViolationType {
  /// Computed velocity between consecutive pings exceeds physical maximum.
  impossibleSpeed,

  /// Two pings share the same GPS timestamp but are >5m apart.
  sameTimestampPositionJump,
}

/// Result of a [KinematicGuard.validate] check between two consecutive
/// [CanonicalFact] events for the same asset.
///
/// Pure domain value object — no Flutter or Supabase dependencies (INV-18).
class KinematicValidationResult extends Equatable {
  final bool isViolation;
  final KinematicViolationType? violationType;

  /// Implied speed in cm/s between the two facts.
  /// Null if elapsed time is 0 (cannot compute).
  final int? impliedSpeedCms;

  /// Maximum allowed speed in cm/s for this validation context.
  final int maxAllowedSpeedCms;

  /// Haversine distance in metres between the two facts.
  final double distanceMeters;

  /// Elapsed seconds between the two GPS timestamps.
  final int elapsedSeconds;

  const KinematicValidationResult._({
    required this.isViolation,
    this.violationType,
    this.impliedSpeedCms,
    required this.maxAllowedSpeedCms,
    required this.distanceMeters,
    required this.elapsedSeconds,
  });

  factory KinematicValidationResult.ok({
    required double distanceMeters,
    required int elapsedSeconds,
    required int? impliedSpeedCms,
    required int maxAllowedSpeedCms,
  }) {
    return KinematicValidationResult._(
      isViolation: false,
      distanceMeters: distanceMeters,
      elapsedSeconds: elapsedSeconds,
      impliedSpeedCms: impliedSpeedCms,
      maxAllowedSpeedCms: maxAllowedSpeedCms,
    );
  }

  factory KinematicValidationResult.violation({
    required KinematicViolationType type,
    required double distanceMeters,
    required int elapsedSeconds,
    required int? impliedSpeedCms,
    required int maxAllowedSpeedCms,
  }) {
    return KinematicValidationResult._(
      isViolation: true,
      violationType: type,
      distanceMeters: distanceMeters,
      elapsedSeconds: elapsedSeconds,
      impliedSpeedCms: impliedSpeedCms,
      maxAllowedSpeedCms: maxAllowedSpeedCms,
    );
  }

  @override
  List<Object?> get props => [
    isViolation,
    violationType,
    impliedSpeedCms,
    maxAllowedSpeedCms,
    distanceMeters,
    elapsedSeconds,
  ];
}
