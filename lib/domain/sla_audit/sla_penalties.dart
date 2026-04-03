import 'package:equatable/equatable.dart';

import '../shared/money.dart';
import 'domain_exception.dart';

/// Value object representing the SLA margin offenders for a shift pattern.
///
/// Financial fields use [Money] (BIGINT cents) — invariant enforced.
/// Non-financial fields use appropriate primitives.
///
/// **Fields:**
/// - [noShowPenaltyBps] — multiplier applied to contractual value on no-show in bps (≥ 10000)
/// - [delayToleranceMinutes] — minutes of lateness before the penalty clock starts (≥ 0)
/// - [delayPenaltyPerMinute] — financial penalty per minute of delay beyond tolerance
/// - [downgradePenaltyFlat] — flat financial penalty when a lower vehicle category is deployed
/// - [noShowThresholdMinutes] — delay ceiling (minutes) after which the system auto-classifies as no-show (≥ 0). Default: 60
/// - [earlyArrivalToleranceMinutes] — early arrival margin (minutes) before it counts as an infraction (≥ 0). Default: 5
/// - [dwellTimeMinutes] — minimum minutes inside geofence to validate the trip (≥ 0). Default: 3
/// - [gracePeriodMinutes] — buffer window (minutes) after scheduled start before engine starts checking infractions (≥ 0). Default: 0
class SLAPenalties extends Equatable {
  /// Multiplier applied to contractual value on no-show. In bps (e.g. 15000 = 1.5x).
  final int noShowPenaltyBps;

  /// Grace period before delay penalty starts. Must be ≥ 0.
  final int delayToleranceMinutes;

  /// Penalty per minute of delay beyond [delayToleranceMinutes].
  /// Stored as [Money] (BIGINT cents). Must be > 0.
  final Money delayPenaltyPerMinute;

  /// Flat penalty applied when the dispatched vehicle is below the contracted category.
  /// Stored as [Money] (BIGINT cents). Must be > 0.
  final Money downgradePenaltyFlat;

  /// Delay (minutes) after which the engine auto-classifies the execution as no-show.
  /// Must be ≥ 0. Default: 60.
  final int noShowThresholdMinutes;

  /// Early arrival tolerance (minutes). Arriving earlier than this margin counts as an
  /// infraction (disturbs client operations). Must be ≥ 0. Default: 5.
  final int earlyArrivalToleranceMinutes;

  /// Minimum time (minutes) the vehicle must remain inside the destination geofence
  /// for the trip to be considered validated. Must be ≥ 0. Default: 3.
  final int dwellTimeMinutes;

  /// Buffer window (minutes) after scheduled start before engine starts checking infractions.
  /// Must be ≥ 0. Default: 0.
  final int gracePeriodMinutes;

  /// Base financial value of a single trip under this shift pattern.
  ///
  /// Used for financial risk summary (Receita Protegida, Exposição No-Show)
  /// and margin erosion calculations. Stored as [Money] (BIGINT cents — INV-2).
  /// Must be > 0.
  ///
  /// Backward compat: absent in JSONB payloads before Bloco 4.3 sprint →
  /// defaults to [Money.zero] via [fromJson] fallback.
  final Money baseTripValue;

  const SLAPenalties._({
    required this.noShowPenaltyBps,
    required this.delayToleranceMinutes,
    required this.delayPenaltyPerMinute,
    required this.downgradePenaltyFlat,
    required this.noShowThresholdMinutes,
    required this.earlyArrivalToleranceMinutes,
    required this.dwellTimeMinutes,
    required this.gracePeriodMinutes,
    required this.baseTripValue,
  });

  /// Creates [SLAPenalties] with validated invariants.
  ///
  /// Throws [DomainException] if any invariant is violated.
  factory SLAPenalties.create({
    required int noShowPenaltyBps,
    required int delayToleranceMinutes,
    required Money delayPenaltyPerMinute,
    required Money downgradePenaltyFlat,
    int noShowThresholdMinutes = 60,
    int earlyArrivalToleranceMinutes = 5,
    int dwellTimeMinutes = 3,
    int gracePeriodMinutes = 0,
    Money baseTripValue = const Money(0),
  }) {
    if (noShowPenaltyBps < 10000) {
      throw const DomainException('noShowPenaltyBps must be >= 10000 (1.0x)');
    }
    if (delayToleranceMinutes < 0) {
      throw const DomainException('delayToleranceMinutes must be >= 0');
    }
    if (delayPenaltyPerMinute.cents <= 0) {
      throw const DomainException(
        'delayPenaltyPerMinute must be greater than 0',
      );
    }
    if (downgradePenaltyFlat.cents <= 0) {
      throw const DomainException(
        'downgradePenaltyFlat must be greater than 0',
      );
    }
    if (noShowThresholdMinutes < 0) {
      throw const DomainException('noShowThresholdMinutes must be >= 0');
    }
    if (earlyArrivalToleranceMinutes < 0) {
      throw const DomainException('earlyArrivalToleranceMinutes must be >= 0');
    }
    if (dwellTimeMinutes < 0) {
      throw const DomainException('dwellTimeMinutes must be >= 0');
    }
    if (gracePeriodMinutes < 0) {
      throw const DomainException('gracePeriodMinutes must be >= 0');
    }
    if (baseTripValue.cents < 0) {
      throw const DomainException('baseTripValue must be >= 0');
    }

    return SLAPenalties._(
      noShowPenaltyBps: noShowPenaltyBps,
      delayToleranceMinutes: delayToleranceMinutes,
      delayPenaltyPerMinute: delayPenaltyPerMinute,
      downgradePenaltyFlat: downgradePenaltyFlat,
      noShowThresholdMinutes: noShowThresholdMinutes,
      earlyArrivalToleranceMinutes: earlyArrivalToleranceMinutes,
      dwellTimeMinutes: dwellTimeMinutes,
      gracePeriodMinutes: gracePeriodMinutes,
      baseTripValue: baseTripValue,
    );
  }

  /// Reconstitutes from persistence without re-validating invariants.
  factory SLAPenalties.reconstitute({
    required int noShowPenaltyBps,
    required int delayToleranceMinutes,
    required Money delayPenaltyPerMinute,
    required Money downgradePenaltyFlat,
    int noShowThresholdMinutes = 60,
    int earlyArrivalToleranceMinutes = 5,
    int dwellTimeMinutes = 3,
    int gracePeriodMinutes = 0,
    Money baseTripValue = const Money(0),
  }) {
    return SLAPenalties._(
      noShowPenaltyBps: noShowPenaltyBps,
      delayToleranceMinutes: delayToleranceMinutes,
      delayPenaltyPerMinute: delayPenaltyPerMinute,
      downgradePenaltyFlat: downgradePenaltyFlat,
      noShowThresholdMinutes: noShowThresholdMinutes,
      earlyArrivalToleranceMinutes: earlyArrivalToleranceMinutes,
      dwellTimeMinutes: dwellTimeMinutes,
      gracePeriodMinutes: gracePeriodMinutes,
      baseTripValue: baseTripValue,
    );
  }

  /// Serializes to JSON for JSONB storage inside [ShiftPattern] payload.
  Map<String, dynamic> toJson() => {
    'noShowPenaltyBps': noShowPenaltyBps,
    'delayToleranceMinutes': delayToleranceMinutes,
    'delayPenaltyPerMinuteCents': delayPenaltyPerMinute.cents,
    'downgradePenaltyFlatCents': downgradePenaltyFlat.cents,
    'noShowThresholdMinutes': noShowThresholdMinutes,
    'earlyArrivalToleranceMinutes': earlyArrivalToleranceMinutes,
    'dwellTimeMinutes': dwellTimeMinutes,
    'gracePeriodMinutes': gracePeriodMinutes,
    'baseTripValueCents': baseTripValue.cents,
  };

  /// Deserializes from JSON stored in [ShiftPattern] JSONB payload.
  /// New fields use `?? default` for backward compatibility with existing plans.
  factory SLAPenalties.fromJson(Map<String, dynamic> json) {
    return SLAPenalties._(
      noShowPenaltyBps:
          json['noShowPenaltyBps'] as int? ??
          ((json['noShowPenaltyMultiplier'] as num).toDouble() * 10000).round(),
      delayToleranceMinutes: json['delayToleranceMinutes'] as int,
      delayPenaltyPerMinute: Money(
        (json['delayPenaltyPerMinuteCents'] as num).toInt(),
      ),
      downgradePenaltyFlat: Money(
        (json['downgradePenaltyFlatCents'] as num).toInt(),
      ),
      noShowThresholdMinutes: (json['noShowThresholdMinutes'] as int?) ?? 60,
      earlyArrivalToleranceMinutes:
          (json['earlyArrivalToleranceMinutes'] as int?) ?? 5,
      dwellTimeMinutes: (json['dwellTimeMinutes'] as int?) ?? 3,
      gracePeriodMinutes: (json['gracePeriodMinutes'] as int?) ?? 0,
      // Backward compat: absent in JSONB before Bloco 4.3 → Money(0).
      baseTripValue: Money((json['baseTripValueCents'] as num?)?.toInt() ?? 0),
    );
  }

  @override
  List<Object?> get props => [
    noShowPenaltyBps,
    delayToleranceMinutes,
    delayPenaltyPerMinute,
    downgradePenaltyFlat,
    noShowThresholdMinutes,
    earlyArrivalToleranceMinutes,
    dwellTimeMinutes,
    gracePeriodMinutes,
    baseTripValue,
  ];
}
