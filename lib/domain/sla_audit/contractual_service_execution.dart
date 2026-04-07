import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

import 'package:veraprob/domain/shared/money.dart';
import 'domain_exception.dart';

/// Internal Entity of the [PlanDeclaration] aggregate.
///
/// Represents a single contractual service execution obligation.
/// Has its own identity via the Service Execution Token (SET),
/// which is generated deterministically from the contractual obligation
/// parameters to guarantee reproducibility and audit consistency.
///
/// **Two creation modes:**
/// - Manual (baseline): [create] — operator declares explicit timestamps + coordinates.
/// - Projected (B2B): [createProjected] — [ShiftProjectionService] derives timestamps
///   from [ShiftPattern] + date and snapshots zone coordinates.
///
/// Equality is based **exclusively** on [setId].
class ContractualServiceExecution extends Equatable {
  // ── Identity ──────────────────────────────────────────────
  /// Service Execution Token — deterministic hash generated internally.
  /// Manual SETs: SHA-256(contractId + scheduledStartTimeUtc).
  /// Projected SETs: SHA-256(planDeclarationId + shiftPatternIndex + operationalDate).
  final String setId;

  // ── Temporal ──────────────────────────────────────────────
  final DateTime scheduledStartTimeUtc;
  final DateTime scheduledEndTimeUtc;

  // ── Spatial — Start Geofence ──────────────────────────────
  /// Snapshotted coordinates. For projected SETs: captured from [OperationalZone]
  /// at projection time — zone updates do NOT affect historical SETs.
  final double startLatitude; // Physical Metric - Double Required
  final double startLongitude; // Physical Metric - Double Required
  final int startRadiusMeters;

  final double endLatitude; // Physical Metric - Double Required
  final double endLongitude; // Physical Metric - Double Required
  final int endRadiusMeters;

  // ── Planning ──────────────────────────────────────────────
  final String? plannedVehicleId;

  // ── Financial ─────────────────────────────────────────────
  /// Contractual value of this service execution obligation.
  final Money contractualValue;

  /// Multiplier applied to contractualValue when the obligation
  /// results in a NoShow. In basis points (e.g., 15000 = 1.5x).
  final int noShowPenaltyBps;

  // ── B2B Projection metadata (null for manually-declared SETs) ──────
  /// Audit trail: ID of the origin [OperationalZone] at projection time.
  /// NOT used for evaluation — [startLatitude/Longitude/RadiusMeters] are used.
  final String? originZoneId;

  /// Audit trail: ID of the destination [OperationalZone] at projection time.
  final String? destinationZoneId;

  /// Calendar date of this service (in the zone's local timezone).
  /// Null for manually-declared SETs.
  final DateTime? operationalDate;

  /// Zero-based index of the [ShiftPattern] within its [PlanDeclaration].
  /// Part of the projected SET idempotency key. Null for manual SETs.
  final int? shiftPatternIndex;

  // ── B2B SLA Penalties snapshot (null for manually-declared SETs) ────
  /// Tolerance window before delay penalty starts. Snapshotted from [SLAPenalties].
  final int? delayToleranceMinutes;

  /// Per-minute delay penalty. Snapshotted from [SLAPenalties.delayPenaltyPerMinute].
  final Money? delayPenaltyPerMinute;

  /// Flat vehicle-downgrade penalty. Snapshotted from [SLAPenalties.downgradePenaltyFlat].
  final Money? downgradePenaltyFlat;

  // ── Private constructor ───────────────────────────────────
  const ContractualServiceExecution._({
    required this.setId,
    required this.scheduledStartTimeUtc,
    required this.scheduledEndTimeUtc,
    required this.startLatitude,
    required this.startLongitude,
    required this.startRadiusMeters,
    required this.endLatitude,
    required this.endLongitude,
    required this.endRadiusMeters,
    this.plannedVehicleId,
    required this.contractualValue,
    required this.noShowPenaltyBps,
    this.originZoneId,
    this.destinationZoneId,
    this.operationalDate,
    this.shiftPatternIndex,
    this.delayToleranceMinutes,
    this.delayPenaltyPerMinute,
    this.downgradePenaltyFlat,
  });

  // ── Manual creation (baseline) ────────────────────────────

  /// Creates a manually-declared [ContractualServiceExecution].
  ///
  /// SET id: SHA-256(contractId + scheduledStartTimeUtc.toIso8601String()).
  /// Throws [DomainException] if any invariant is violated.
  static ContractualServiceExecution create({
    required String contractId,
    required DateTime scheduledStartTimeUtc,
    required DateTime scheduledEndTimeUtc,
    required double startLatitude, // Physical Metric - Double Required
    required double startLongitude, // Physical Metric - Double Required
    required int startRadiusMeters,
    required double endLatitude, // Physical Metric - Double Required
    required double endLongitude, // Physical Metric - Double Required
    required int endRadiusMeters,
    String? plannedVehicleId,
    required Money contractualValue,
    required int noShowPenaltyBps,
  }) {
    if (!scheduledEndTimeUtc.isAfter(scheduledStartTimeUtc)) {
      throw const DomainException(
        'scheduledEndTimeUtc must be after scheduledStartTimeUtc',
      );
    }
    _validateLatitude(startLatitude, 'startLatitude');
    _validateLongitude(startLongitude, 'startLongitude');
    _validateRadius(startRadiusMeters, 'startRadiusMeters');
    _validateLatitude(endLatitude, 'endLatitude');
    _validateLongitude(endLongitude, 'endLongitude');
    _validateRadius(endRadiusMeters, 'endRadiusMeters');
    if (contractualValue.cents <= 0) {
      throw const DomainException('contractualValue must be greater than 0');
    }
    if (noShowPenaltyBps < 10000) {
      throw const DomainException('noShowPenaltyBps must be >= 10000 (1.0x)');
    }

    return ContractualServiceExecution._(
      setId: _generateManualSetId(contractId, scheduledStartTimeUtc),
      scheduledStartTimeUtc: scheduledStartTimeUtc,
      scheduledEndTimeUtc: scheduledEndTimeUtc,
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      startRadiusMeters: startRadiusMeters,
      endLatitude: endLatitude,
      endLongitude: endLongitude,
      endRadiusMeters: endRadiusMeters,
      plannedVehicleId: plannedVehicleId,
      contractualValue: contractualValue,
      noShowPenaltyBps: noShowPenaltyBps,
    );
  }

  // ── Projected creation (B2B) ──────────────────────────────

  /// Creates a projected [ContractualServiceExecution] from a [ShiftPattern].
  ///
  /// SET id: SHA-256(planDeclarationId + shiftPatternIndex + operationalDate).
  /// Zone coordinates are snapshotted at call time — zone updates do NOT
  /// retroactively change this SET (preserves replay determinism).
  ///
  /// Throws [DomainException] if any invariant is violated.
  static ContractualServiceExecution createProjected({
    required String planDeclarationId,
    required int shiftPatternIndex,
    required DateTime operationalDate,
    required DateTime scheduledStartTimeUtc,
    required DateTime scheduledEndTimeUtc,
    // Origin zone — coordinates snapshotted from OperationalZone
    required String originZoneId,
    required double startLatitude, // Physical Metric - Double Required
    required double startLongitude, // Physical Metric - Double Required
    required int startRadiusMeters,
    // Destination zone — coordinates snapshotted from OperationalZone
    required String destinationZoneId,
    required double endLatitude, // Physical Metric - Double Required
    required double endLongitude, // Physical Metric - Double Required
    required int endRadiusMeters,
    required Money contractualValue,
    // SLAPenalties snapshot
    required int noShowPenaltyBps,
    required int delayToleranceMinutes,
    required Money delayPenaltyPerMinute,
    required Money downgradePenaltyFlat,
    String? plannedVehicleId,
  }) {
    if (!scheduledEndTimeUtc.isAfter(scheduledStartTimeUtc)) {
      throw const DomainException(
        'scheduledEndTimeUtc must be after scheduledStartTimeUtc',
      );
    }
    _validateLatitude(startLatitude, 'startLatitude');
    _validateLongitude(startLongitude, 'startLongitude');
    _validateRadius(startRadiusMeters, 'startRadiusMeters');
    _validateLatitude(endLatitude, 'endLatitude');
    _validateLongitude(endLongitude, 'endLongitude');
    _validateRadius(endRadiusMeters, 'endRadiusMeters');
    if (contractualValue.cents <= 0) {
      throw const DomainException('contractualValue must be greater than 0');
    }
    if (noShowPenaltyBps < 10000) {
      throw const DomainException('noShowPenaltyBps must be >= 10000 (1.0x)');
    }

    return ContractualServiceExecution._(
      setId: _generateProjectedSetId(
        planDeclarationId,
        shiftPatternIndex,
        operationalDate,
      ),
      scheduledStartTimeUtc: scheduledStartTimeUtc,
      scheduledEndTimeUtc: scheduledEndTimeUtc,
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      startRadiusMeters: startRadiusMeters,
      endLatitude: endLatitude,
      endLongitude: endLongitude,
      endRadiusMeters: endRadiusMeters,
      plannedVehicleId: plannedVehicleId,
      contractualValue: contractualValue,
      noShowPenaltyBps: noShowPenaltyBps,
      originZoneId: originZoneId,
      destinationZoneId: destinationZoneId,
      operationalDate: operationalDate,
      shiftPatternIndex: shiftPatternIndex,
      delayToleranceMinutes: delayToleranceMinutes,
      delayPenaltyPerMinute: delayPenaltyPerMinute,
      downgradePenaltyFlat: downgradePenaltyFlat,
    );
  }

  // ── Reconstitution ────────────────────────────────────────

  /// Reconstitutes a [ContractualServiceExecution] from persistence.
  /// Does NOT generate a new SET; uses the provided [setId].
  static ContractualServiceExecution reconstitute({
    required String setId,
    required DateTime scheduledStartTimeUtc,
    required DateTime scheduledEndTimeUtc,
    required double startLatitude, // Physical Metric - Double Required
    required double startLongitude, // Physical Metric - Double Required
    required int startRadiusMeters,
    required double endLatitude, // Physical Metric - Double Required
    required double endLongitude, // Physical Metric - Double Required
    required int endRadiusMeters,
    String? plannedVehicleId,
    required Money contractualValue,
    required int noShowPenaltyBps,
    String? originZoneId,
    String? destinationZoneId,
    DateTime? operationalDate,
    int? shiftPatternIndex,
    int? delayToleranceMinutes,
    Money? delayPenaltyPerMinute,
    Money? downgradePenaltyFlat,
  }) {
    return ContractualServiceExecution._(
      setId: setId,
      scheduledStartTimeUtc: scheduledStartTimeUtc,
      scheduledEndTimeUtc: scheduledEndTimeUtc,
      startLatitude: startLatitude,
      startLongitude: startLongitude,
      startRadiusMeters: startRadiusMeters,
      endLatitude: endLatitude,
      endLongitude: endLongitude,
      endRadiusMeters: endRadiusMeters,
      plannedVehicleId: plannedVehicleId,
      contractualValue: contractualValue,
      noShowPenaltyBps: noShowPenaltyBps,
      originZoneId: originZoneId,
      destinationZoneId: destinationZoneId,
      operationalDate: operationalDate,
      shiftPatternIndex: shiftPatternIndex,
      delayToleranceMinutes: delayToleranceMinutes,
      delayPenaltyPerMinute: delayPenaltyPerMinute,
      downgradePenaltyFlat: downgradePenaltyFlat,
    );
  }

  // ── Helpers ───────────────────────────────────────────────

  /// Whether this SET was generated by [ShiftProjectionService] (vs manually declared).
  bool get isProjected => shiftPatternIndex != null;

  /// SET id for manually-declared SETs: SHA-256(contractId + scheduledStartTimeUtc).
  static String _generateManualSetId(
    String contractId,
    DateTime scheduledStartTimeUtc,
  ) {
    final input = '$contractId|${scheduledStartTimeUtc.toIso8601String()}';
    return _sha256(input);
  }

  /// SET id for projected SETs: SHA-256(planDeclarationId + shiftPatternIndex + operationalDate).
  /// Deterministic: same plan + same pattern + same date → same id.
  static String _generateProjectedSetId(
    String planDeclarationId,
    int shiftPatternIndex,
    DateTime operationalDate,
  ) {
    final dateKey =
        '${operationalDate.year}-${operationalDate.month.toString().padLeft(2, '0')}-${operationalDate.day.toString().padLeft(2, '0')}';
    final input = '$planDeclarationId|$shiftPatternIndex|$dateKey';
    return _sha256(input);
  }

  static String _sha256(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static void _validateLatitude(double value, String fieldName) { // Physical Metric - Double Required
    if (value < -90 || value > 90) {
      throw DomainException('$fieldName must be between -90 and 90');
    }
  }

  static void _validateLongitude(double value, String fieldName) { // Physical Metric - Double Required
    if (value < -180 || value > 180) {
      throw DomainException('$fieldName must be between -180 and 180');
    }
  }

  static void _validateRadius(int value, String fieldName) {
    if (value <= 0) {
      throw DomainException('$fieldName must be greater than 0');
    }
  }

  /// Equality is based **exclusively** on [setId].
  @override
  List<Object?> get props => [setId];
}
