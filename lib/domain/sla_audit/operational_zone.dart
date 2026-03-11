import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import 'domain_exception.dart';

/// Domain entity representing a named geofenced area owned by an organization.
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
  final double latitude;
  final double longitude;
  final int radiusMeters;

  const OperationalZone._({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  /// Creates a new [OperationalZone] with a generated UUID and validated invariants.
  ///
  /// Throws [DomainException] if any invariant is violated.
  static OperationalZone create({
    required String organizationId,
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) {
    if (organizationId.isEmpty) {
      throw const DomainException('organizationId must not be empty');
    }
    _validateName(name);
    _validateLatitude(latitude);
    _validateLongitude(longitude);
    _validateRadius(radiusMeters);

    return OperationalZone._(
      id: const Uuid().v4(),
      organizationId: organizationId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
  }

  /// Reconstitutes an [OperationalZone] from persistence without re-validating.
  static OperationalZone reconstitute({
    required String id,
    required String organizationId,
    required String name,
    required double latitude,
    required double longitude,
    required int radiusMeters,
  }) {
    return OperationalZone._(
      id: id,
      organizationId: organizationId,
      name: name,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
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
    if (value < -90 || value > 90) {
      throw const DomainException('latitude must be between -90 and 90');
    }
  }

  static void _validateLongitude(double value) {
    if (value < -180 || value > 180) {
      throw const DomainException('longitude must be between -180 and 180');
    }
  }

  static void _validateRadius(int value) {
    if (value <= 0 || value > 50000) {
      throw const DomainException(
        'radiusMeters must be between 1 and 50000',
      );
    }
  }

  @override
  List<Object?> get props => [id];
}
