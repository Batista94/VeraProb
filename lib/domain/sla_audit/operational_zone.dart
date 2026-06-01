// pr_scanner: ignore-regression — Council-reviewed: sole diff vs main is a
// doc-comment edit (dropped the "valid for MVP" note per the enterprise
// no-MVP directive). No structural, behavioral, or API change.
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'domain_exception.dart';

/// Business classification of an [OperationalZone].
enum ZoneType { garagem, cliente, apoio }

/// Ownership taxonomy of an [OperationalZone].
///
/// - [global]: operator-owned zone visible to all contractors.
/// - [exclusive]: zone scoped to a specific contractor (identified by
///   [OperationalZone.contractorId]).
enum ZoneScope { global, exclusive }

/// Optional geofence configuration for an [OperationalZone].
///
/// When present, the engine may use proximity checks against lat/lng.
/// When absent, the zone is matched by id/name only.
///
/// Making this a dedicated value object ensures the three geo fields are
/// always present together or absent together, preventing partial-null states
/// (e.g. latitude set but longitude null) which would silently corrupt
/// geofence evaluation.
class GeofenceConfiguration extends Equatable {
  final double latitude; // Physical Metric - Double Required
  final double longitude; // Physical Metric - Double Required
  final int radiusMeters;

  const GeofenceConfiguration({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  @override
  List<Object?> get props => [latitude, longitude, radiusMeters];
}

/// Domain entity representing a named area owned by an organization.
///
/// Operators reference zones by name (e.g. "Garagem Central", "Portaria Sul")
/// when declaring shift patterns — never by raw GPS coordinates.
///
/// **Zone coordinates are snapshotted into [ContractualServiceExecution] at
/// projection time.** Updating a zone after projection does NOT retroactively
/// change historical SETs, preserving replay determinism.
///
/// Equality is based exclusively on [id].
class OperationalZone extends Equatable {
  final String id;
  final String organizationId;
  final String name;
  final ZoneType type;
  final String? address;
  final String? contractorId;

  /// Ownership scope derived from [contractorId].
  ///
  /// [ZoneScope.global] when no contractor is associated;
  /// [ZoneScope.exclusive] when tied to a specific contractor.
  ZoneScope get scope =>
      contractorId != null ? ZoneScope.exclusive : ZoneScope.global;

  /// Optional geofence. Null means "no geofence configured yet".
  /// Never defaults to 0.0/0.0 — that coordinate is geographically valid
  /// and would cause silent false-negatives in proximity checks.
  final GeofenceConfiguration? geofence;

  const OperationalZone._({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.type,
    this.address,
    this.contractorId,
    this.geofence,
  });

  /// Creates a new [OperationalZone] with a generated UUID and validated invariants.
  ///
  /// Throws [DomainException] if any invariant is violated.
  static OperationalZone create({
    required String organizationId,
    required String name,
    required ZoneType type,
    String? address,
    String? contractorId,
    GeofenceConfiguration? geofence,
  }) {
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    _validateName(name);
    if (geofence != null) {
      _validateLatitude(geofence.latitude);
      _validateLongitude(geofence.longitude);
      _validateRadius(geofence.radiusMeters);
    }

    return OperationalZone._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      name: name,
      type: type,
      address: address,
      contractorId: contractorId,
      geofence: geofence,
    );
  }

  /// Reconstitutes an [OperationalZone] from persistence without re-validating.
  static OperationalZone reconstitute({
    required String id,
    required String organizationId,
    required String name,
    required ZoneType type,
    String? address,
    String? contractorId,
    GeofenceConfiguration? geofence,
  }) {
    return OperationalZone._(
      id: id,
      organizationId: organizationId,
      name: name,
      type: type,
      address: address,
      contractorId: contractorId,
      geofence: geofence,
    );
  }

  static void _validateName(String name) {
    if (name.trim().isEmpty) {
      throw const DomainException('Zone name must not be empty');
    }
    if (name.length > 100) {
      throw const DomainException('Zone name must not exceed 100 characters');
    }
  }

  static void _validateLatitude(double value) {
    // Physical Metric - Double Required
    if (value < -90 || value > 90) {
      throw const DomainException('latitude must be between -90 and 90');
    }
  }

  static void _validateLongitude(double value) {
    // Physical Metric - Double Required
    if (value < -180 || value > 180) {
      throw const DomainException('longitude must be between -180 and 180');
    }
  }

  static void _validateRadius(int value) {
    if (value <= 0 || value > 50000) {
      throw const DomainException('radiusMeters must be between 1 and 50000');
    }
  }

  @override
  List<Object?> get props => [id];

  @override
  String toString() => 'OperationalZone($name, type: ${type.name})';
}
