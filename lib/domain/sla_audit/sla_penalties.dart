import 'package:equatable/equatable.dart';

import '../shared/money.dart';
import 'domain_exception.dart';

/// Value object representing the SLA margin offenders for a shift pattern.
///
/// Financial fields use [Money] (BIGINT cents) — invariant enforced.
/// Non-financial fields use appropriate primitives.
///
/// **Fields:**
/// - [noShowPenaltyMultiplier] — multiplier applied to contractual value on no-show (≥ 1.0)
/// - [delayToleranceMinutes] — minutes of lateness before the penalty clock starts (≥ 0)
/// - [delayPenaltyPerMinute] — financial penalty per minute of delay beyond tolerance
/// - [downgradePenaltyFlat] — flat financial penalty when a lower vehicle category is deployed
class SLAPenalties extends Equatable {
  /// Multiplier applied to contractual value on no-show. Must be ≥ 1.0.
  /// Stored as double because it is a ratio, not a monetary amount.
  final double noShowPenaltyMultiplier;

  /// Grace period before delay penalty starts. Must be ≥ 0.
  final int delayToleranceMinutes;

  /// Penalty per minute of delay beyond [delayToleranceMinutes].
  /// Stored as [Money] (BIGINT cents). Must be > 0.
  final Money delayPenaltyPerMinute;

  /// Flat penalty applied when the dispatched vehicle is below the contracted category.
  /// Stored as [Money] (BIGINT cents). Must be > 0.
  final Money downgradePenaltyFlat;

  const SLAPenalties._({
    required this.noShowPenaltyMultiplier,
    required this.delayToleranceMinutes,
    required this.delayPenaltyPerMinute,
    required this.downgradePenaltyFlat,
  });

  /// Creates [SLAPenalties] with validated invariants.
  ///
  /// Throws [DomainException] if any invariant is violated.
  factory SLAPenalties.create({
    required double noShowPenaltyMultiplier,
    required int delayToleranceMinutes,
    required Money delayPenaltyPerMinute,
    required Money downgradePenaltyFlat,
  }) {
    if (noShowPenaltyMultiplier < 1.0) {
      throw const DomainException(
        'noShowPenaltyMultiplier must be >= 1.0',
      );
    }
    if (delayToleranceMinutes < 0) {
      throw const DomainException(
        'delayToleranceMinutes must be >= 0',
      );
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

    return SLAPenalties._(
      noShowPenaltyMultiplier: noShowPenaltyMultiplier,
      delayToleranceMinutes: delayToleranceMinutes,
      delayPenaltyPerMinute: delayPenaltyPerMinute,
      downgradePenaltyFlat: downgradePenaltyFlat,
    );
  }

  /// Reconstitutes from persistence without re-validating invariants.
  factory SLAPenalties.reconstitute({
    required double noShowPenaltyMultiplier,
    required int delayToleranceMinutes,
    required Money delayPenaltyPerMinute,
    required Money downgradePenaltyFlat,
  }) {
    return SLAPenalties._(
      noShowPenaltyMultiplier: noShowPenaltyMultiplier,
      delayToleranceMinutes: delayToleranceMinutes,
      delayPenaltyPerMinute: delayPenaltyPerMinute,
      downgradePenaltyFlat: downgradePenaltyFlat,
    );
  }

  /// Serializes to JSON for JSONB storage inside [ShiftPattern] payload.
  Map<String, dynamic> toJson() => {
        'noShowPenaltyMultiplier': noShowPenaltyMultiplier,
        'delayToleranceMinutes': delayToleranceMinutes,
        'delayPenaltyPerMinuteCents': delayPenaltyPerMinute.cents,
        'downgradePenaltyFlatCents': downgradePenaltyFlat.cents,
      };

  /// Deserializes from JSON stored in [ShiftPattern] JSONB payload.
  factory SLAPenalties.fromJson(Map<String, dynamic> json) {
    return SLAPenalties._(
      noShowPenaltyMultiplier:
          (json['noShowPenaltyMultiplier'] as num).toDouble(),
      delayToleranceMinutes: json['delayToleranceMinutes'] as int,
      delayPenaltyPerMinute:
          Money((json['delayPenaltyPerMinuteCents'] as num).toInt()),
      downgradePenaltyFlat:
          Money((json['downgradePenaltyFlatCents'] as num).toInt()),
    );
  }

  @override
  List<Object?> get props => [
        noShowPenaltyMultiplier,
        delayToleranceMinutes,
        delayPenaltyPerMinute,
        downgradePenaltyFlat,
      ];
}
