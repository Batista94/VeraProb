import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

import 'domain_exception.dart';

/// Internal Entity of the [PlanDeclaration] aggregate.
///
/// Represents a single contractual service execution obligation.
/// Has its own identity via the Service Execution Token (SET),
/// which is generated deterministically from the contractual obligation
/// parameters to guarantee reproducibility and audit consistency.
///
/// Equality is based **exclusively** on [setId].
class ContractualServiceExecution extends Equatable {
  // ── Identity ──────────────────────────────────────────────
  /// Service Execution Token — deterministic hash of the contractual
  /// obligation parameters. Generated internally, never from external input.
  final String setId;

  // ── Temporal ──────────────────────────────────────────────
  final DateTime scheduledStartTimeUtc;
  final DateTime scheduledEndTimeUtc;

  // ── Spatial — Start Geofence ──────────────────────────────
  final double startLatitude;
  final double startLongitude;
  final int startRadiusMeters;

  // ── Spatial — End Geofence ────────────────────────────────
  final double endLatitude;
  final double endLongitude;
  final int endRadiusMeters;

  // ── Planning ──────────────────────────────────────────────
  final String? plannedVehicleId;

  // ── Financial ─────────────────────────────────────────────
  /// Contractual value of this service execution obligation.
  final double contractualValue;

  /// Multiplier applied to contractualValue when the obligation
  /// results in a NoShow. Must be >= 1.0.
  final double noShowPenaltyMultiplier;

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
    required this.noShowPenaltyMultiplier,
  });

  /// Creates a [ContractualServiceExecution] with a deterministic SET
  /// and validates all spatial/temporal invariants.
  ///
  /// The SET is generated as a SHA-256 hash of:
  /// `contractId + scheduledStartTimeUtc.toIso8601String()`
  ///
  /// Throws [DomainException] if any invariant is violated.
  static ContractualServiceExecution create({
    required String contractId,
    required DateTime scheduledStartTimeUtc,
    required DateTime scheduledEndTimeUtc,
    required double startLatitude,
    required double startLongitude,
    required int startRadiusMeters,
    required double endLatitude,
    required double endLongitude,
    required int endRadiusMeters,
    String? plannedVehicleId,
    required double contractualValue,
    required double noShowPenaltyMultiplier,
  }) {
    // ── Temporal invariant ────────────────────────────────
    if (!scheduledEndTimeUtc.isAfter(scheduledStartTimeUtc)) {
      throw const DomainException(
        'scheduledEndTimeUtc must be after scheduledStartTimeUtc',
      );
    }

    // ── Spatial invariants — Start geofence ───────────────
    _validateLatitude(startLatitude, 'startLatitude');
    _validateLongitude(startLongitude, 'startLongitude');
    _validateRadius(startRadiusMeters, 'startRadiusMeters');

    // ── Spatial invariants — End geofence ─────────────────
    _validateLatitude(endLatitude, 'endLatitude');
    _validateLongitude(endLongitude, 'endLongitude');
    _validateRadius(endRadiusMeters, 'endRadiusMeters');

    // ── Financial invariants ──────────────────────────────
    if (contractualValue <= 0) {
      throw const DomainException('contractualValue must be greater than 0');
    }
    if (noShowPenaltyMultiplier < 1.0) {
      throw const DomainException('noShowPenaltyMultiplier must be >= 1.0');
    }

    // ── Generate deterministic SET ────────────────────────
    final setId = _generateSetId(contractId, scheduledStartTimeUtc);

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
      noShowPenaltyMultiplier: noShowPenaltyMultiplier,
    );
  }

  /// Generates a deterministic Service Execution Token (SET) from
  /// the contractual obligation parameters.
  static String _generateSetId(
    String contractId,
    DateTime scheduledStartTimeUtc,
  ) {
    final input = '$contractId|${scheduledStartTimeUtc.toIso8601String()}';
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  static void _validateLatitude(double value, String fieldName) {
    if (value < -90 || value > 90) {
      throw DomainException('$fieldName must be between -90 and 90');
    }
  }

  static void _validateLongitude(double value, String fieldName) {
    if (value < -180 || value > 180) {
      throw DomainException('$fieldName must be between -180 and 180');
    }
  }

  static void _validateRadius(int value, String fieldName) {
    if (value <= 0) {
      throw DomainException('$fieldName must be greater than 0');
    }
  }

  /// Reconstitutes a [ContractualServiceExecution] from persistence.
  /// Does NOT generate a new SET; uses the provided one.
  static ContractualServiceExecution reconstitute({
    required String setId,
    required DateTime scheduledStartTimeUtc,
    required DateTime scheduledEndTimeUtc,
    required double startLatitude,
    required double startLongitude,
    required int startRadiusMeters,
    required double endLatitude,
    required double endLongitude,
    required int endRadiusMeters,
    String? plannedVehicleId,
    required double contractualValue,
    required double noShowPenaltyMultiplier,
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
      noShowPenaltyMultiplier: noShowPenaltyMultiplier,
    );
  }

  /// Equality is based **exclusively** on [setId].
  @override
  List<Object?> get props => [setId];
}
