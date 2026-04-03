/// Typed evidence hierarchy for [EvaluationDecision].
///
/// Replaces `Map<String, dynamic>` for the forensic evidence field, enforcing
/// compile-time safety on evidence shapes emitted by the EvaluationEngine.
///
/// Serialization contract:
/// - [toJson] always emits a `_type` discriminator key for future deserialization.
/// - [fromJson] falls back to [GenericEvidencePayload] when `_type` is absent
///   (existing DB records written before this sealed class was introduced).
sealed class EvidencePayload {
  const EvidencePayload();

  Map<String, dynamic> toJson();

  factory EvidencePayload.fromJson(Map<String, dynamic> json) {
    final type = json['_type'] as String?;
    return switch (type) {
      'dwell_requirement' => DwellRequirementEvidence.fromJson(json),
      'speed_violation' => SpeedViolationEvidence.fromJson(json),
      'geofence_binding' => GeofenceBindingEvidence.fromJson(json),
      'penalty_assessed' => PenaltyAssessedEvidence.fromJson(json),
      'expiration_sweep' => ExpirationSweepEvidence.fromJson(json),
      _ => GenericEvidencePayload(json),
    };
  }
}

/// Evidence that a dwell-time rule parameter was read from rule config.
final class DwellRequirementEvidence extends EvidencePayload {
  final int requiredDwellSeconds;
  final String parameterSource;

  const DwellRequirementEvidence({
    required this.requiredDwellSeconds,
    required this.parameterSource,
  });

  @override
  Map<String, dynamic> toJson() => {
    '_type': 'dwell_requirement',
    'required_dwell_seconds': requiredDwellSeconds,
    'parameter_source': parameterSource,
  };

  factory DwellRequirementEvidence.fromJson(Map<String, dynamic> json) =>
      DwellRequirementEvidence(
        requiredDwellSeconds: json['required_dwell_seconds'] as int,
        parameterSource: json['parameter_source'] as String,
      );
}

/// Evidence for a speed violation sanction (INV-23).
final class SpeedViolationEvidence extends EvidencePayload {
  final double actualSpeedKmh; // Physical Metric - Double Required
  final double limitSpeedKmh; // Physical Metric - Double Required

  const SpeedViolationEvidence({
    required this.actualSpeedKmh,
    required this.limitSpeedKmh,
  });

  @override
  Map<String, dynamic> toJson() => {
    '_type': 'speed_violation',
    'actual_speed_kmh': actualSpeedKmh,
    'limit_speed_kmh': limitSpeedKmh,
  };

  factory SpeedViolationEvidence.fromJson(Map<String, dynamic> json) =>
      SpeedViolationEvidence(
        actualSpeedKmh: (json['actual_speed_kmh'] as num).toDouble(),
        limitSpeedKmh: (json['limit_speed_kmh'] as num).toDouble(),
      );
}

/// Evidence produced when a vehicle successfully binds to a geofence.
final class GeofenceBindingEvidence extends EvidencePayload {
  final double distanceMeters; // Physical Metric - Double Required
  final int allowedRadiusMeters;
  final int actualDwellSeconds;
  final int requiredDwellSeconds;

  const GeofenceBindingEvidence({
    required this.distanceMeters,
    required this.allowedRadiusMeters,
    required this.actualDwellSeconds,
    required this.requiredDwellSeconds,
  });

  @override
  Map<String, dynamic> toJson() => {
    '_type': 'geofence_binding',
    'distance_meters': distanceMeters,
    'allowed_radius_meters': allowedRadiusMeters,
    'actual_dwell_seconds': actualDwellSeconds,
    'required_dwell_seconds': requiredDwellSeconds,
  };

  factory GeofenceBindingEvidence.fromJson(Map<String, dynamic> json) =>
      GeofenceBindingEvidence(
        distanceMeters: (json['distance_meters'] as num).toDouble(),
        allowedRadiusMeters: json['allowed_radius_meters'] as int,
        actualDwellSeconds: json['actual_dwell_seconds'] as int,
        requiredDwellSeconds: json['required_dwell_seconds'] as int,
      );
}

/// Evidence for a no-show penalty assessment.
final class PenaltyAssessedEvidence extends EvidencePayload {
  final int? penaltyAmountCents;

  const PenaltyAssessedEvidence({this.penaltyAmountCents});

  @override
  Map<String, dynamic> toJson() => {
    '_type': 'penalty_assessed',
    'penalty_amount_cents': penaltyAmountCents,
  };

  factory PenaltyAssessedEvidence.fromJson(Map<String, dynamic> json) =>
      PenaltyAssessedEvidence(
        penaltyAmountCents: json['penalty_amount_cents'] as int?,
      );
}

/// Evidence emitted when the engine sweeps an expired obligation.
final class ExpirationSweepEvidence extends EvidencePayload {
  final String scheduledWindowEndUtc;
  final String evaluatedAtUtc;
  final int expiredBySeconds;

  const ExpirationSweepEvidence({
    required this.scheduledWindowEndUtc,
    required this.evaluatedAtUtc,
    required this.expiredBySeconds,
  });

  @override
  Map<String, dynamic> toJson() => {
    '_type': 'expiration_sweep',
    'scheduled_window_end_utc': scheduledWindowEndUtc,
    'evaluated_at_utc': evaluatedAtUtc,
    'expired_by_seconds': expiredBySeconds,
  };

  factory ExpirationSweepEvidence.fromJson(Map<String, dynamic> json) =>
      ExpirationSweepEvidence(
        scheduledWindowEndUtc: json['scheduled_window_end_utc'] as String,
        evaluatedAtUtc: json['evaluated_at_utc'] as String,
        expiredBySeconds: json['expired_by_seconds'] as int,
      );
}

/// Fallback for legacy evidence records stored without a `_type` discriminator,
/// or for engine subtypes not yet migrated to this sealed hierarchy.
///
/// // architectural-note: This class exists solely for backwards compatibility
/// with JSONB rows written before the EvidencePayload sealed class was
/// introduced. New evidence shapes MUST use a typed subclass above.
final class GenericEvidencePayload extends EvidencePayload {
  final Map<String, dynamic> rawData;

  const GenericEvidencePayload(this.rawData);

  @override
  Map<String, dynamic> toJson() => rawData;
}
