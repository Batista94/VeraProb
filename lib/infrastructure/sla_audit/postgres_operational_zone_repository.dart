import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:veraprob/domain/sla_audit/domain_exception.dart';
import 'package:veraprob/domain/sla_audit/operational_zone.dart';
import 'package:veraprob/domain/sla_audit/operational_zone_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Postgres implementation of [OperationalZoneRepository].
///
/// RLS guarantees tenant isolation: all queries are scoped to the
/// authenticated user's organization via JWT `app_metadata.org_id`.
class PostgresOperationalZoneRepository extends BasePostgresRepository
    implements OperationalZoneRepository {
  PostgresOperationalZoneRepository(super.client);

  @override
  Future<void> save(OperationalZone zone) async {
    try {
      await client.from('operational_zones').upsert({
        'id': zone.id,
        'organization_id': zone.organizationId,
        'name': zone.name,
        'type': zone.type.name,
        'address': zone.address,
        'latitude': zone.geofence?.latitude,
        'longitude': zone.geofence?.longitude,
        'radius_meters': zone.geofence?.radiusMeters,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        throw const DomainException(
          'Já existe uma Zona Operacional com este nome na sua organização.',
        );
      }
      rethrow;
    }
  }

  @override
  Future<OperationalZone?> findById(
    String id, {
    required String organizationId,
  }) async {
    final data = await client
        .from('operational_zones')
        .select()
        .eq('id', id)
        .eq('organization_id', organizationId)
        .maybeSingle();

    if (data == null) return null;
    return _mapToEntity(data);
  }

  @override
  Future<List<OperationalZone>> findByOrganization(
    String organizationId,
  ) async {
    final List<dynamic> data = await client
        .from('operational_zones')
        .select()
        .eq('organization_id', organizationId)
        .order('name', ascending: true);

    return data.map((d) => _mapToEntity(d)).toList();
  }

  OperationalZone _mapToEntity(Map<String, dynamic> data) {
    final lat = (data['latitude'] as num?)?.toDouble();
    final lng = (data['longitude'] as num?)?.toDouble();
    final radius = data['radius_meters'] as int?;

    final geofence = (lat != null && lng != null && radius != null)
        ? GeofenceConfiguration(
            latitude: lat,
            longitude: lng,
            radiusMeters: radius,
          )
        : null;

    final typeRaw = data['type'] as String? ?? 'garagem';
    final type = ZoneType.values.firstWhere(
      (e) => e.name == typeRaw,
      orElse: () => ZoneType.garagem,
    );

    return OperationalZone.reconstitute(
      id: data['id'],
      organizationId: data['organization_id'],
      name: data['name'],
      type: type,
      address: data['address'] as String?,
      geofence: geofence,
    );
  }
}
