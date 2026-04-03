import 'package:veraprob/domain/sla_audit/operational_zone.dart';

/// Flat read model for [OperationalZone] used in presentation layer.
///
/// Geofence fields are flattened (no nested VO) to simplify form binding.
/// Coordinates remain `double` — Physical Metric, not currency.
class OperationalZoneView {
  final String id;
  final String organizationId;
  final String name;
  final ZoneType type;
  final ZoneScope scope;
  final String? address;
  final String? contractorId;
  final double? geofenceLat; // Physical Metric - Double Required
  final double? geofenceLng; // Physical Metric - Double Required
  final int? geofenceRadiusMeters;

  const OperationalZoneView({
    required this.id,
    required this.organizationId,
    required this.name,
    required this.type,
    required this.scope,
    this.address,
    this.contractorId,
    this.geofenceLat,
    this.geofenceLng,
    this.geofenceRadiusMeters,
  });

  factory OperationalZoneView.fromDomain(OperationalZone zone) {
    return OperationalZoneView(
      id: zone.id,
      organizationId: zone.organizationId,
      name: zone.name,
      type: zone.type,
      scope: zone.scope,
      address: zone.address,
      contractorId: zone.contractorId,
      geofenceLat: zone.geofence?.latitude,
      geofenceLng: zone.geofence?.longitude,
      geofenceRadiusMeters: zone.geofence?.radiusMeters,
    );
  }

  factory OperationalZoneView.fromRow(Map<String, Object?> row) {
    final typeStr = row['type'] as String;
    final scopeStr = row['zone_scope'] as String? ?? 'global';
    return OperationalZoneView(
      id: row['id'] as String,
      organizationId: row['organization_id'] as String,
      name: row['name'] as String,
      type: ZoneType.values.firstWhere((e) => e.name == typeStr),
      scope: ZoneScope.values.firstWhere((e) => e.name == scopeStr),
      address: row['address'] as String?,
      contractorId: row['contractor_id'] as String?,
      geofenceLat: (row['geofence_lat'] as num?)?.toDouble(),
      geofenceLng: (row['geofence_lng'] as num?)?.toDouble(),
      geofenceRadiusMeters: (row['geofence_radius_meters'] as num?)?.toInt(),
    );
  }
}
