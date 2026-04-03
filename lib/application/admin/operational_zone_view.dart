import 'package:veraprob/domain/sla_audit/operational_zone.dart';

/// Read model for an operational zone used in the presentation layer.
class OperationalZoneView {
  final String id;
  final String organizationId;
  final String name;
  final ZoneType type;
  final String? address;
  final String? contractorId;
  final String? contractorLabel;
  final GeofenceView? geofence;

  ZoneScope get scope => (contractorId != null || contractorLabel != null)
      ? ZoneScope.exclusive
      : ZoneScope.global;

  const OperationalZoneView({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.type,
    this.address,
    this.contractorId,
    this.contractorLabel,
    this.geofence,
  });

  factory OperationalZoneView.fromDomain(OperationalZone domain) {
    return OperationalZoneView(
      id: domain.id,
      organizationId: domain.organizationId,
      name: domain.name,
      type: domain.type,
      address: domain.address,
      contractorId: domain.contractorId,
      contractorLabel: domain.contractorLabel,
      geofence: domain.geofence != null
          ? GeofenceView.fromDomain(domain.geofence!)
          : null,
    );
  }

  OperationalZone toDomain() {
    return OperationalZone.reconstitute(
      id: id,
      organizationId: organizationId,
      name: name,
      type: type,
      address: address,
      contractorId: contractorId,
      contractorLabel: contractorLabel,
      geofence: geofence?.toDomain(),
    );
  }
}

class GeofenceView {
  final double latitude;
  final double longitude;
  final int radiusMeters;

  const GeofenceView({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  factory GeofenceView.fromDomain(GeofenceConfiguration domain) {
    return GeofenceView(
      latitude: domain.latitude,
      longitude: domain.longitude,
      radiusMeters: domain.radiusMeters,
    );
  }

  GeofenceConfiguration toDomain() {
    return GeofenceConfiguration(
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
  }
}
