import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/supabase_client.dart';
import '../../domain/sla_audit/operational_zone.dart';
import '../../domain/sla_audit/operational_zone_repository.dart';

/// Postgres implementation of [OperationalZoneRepository].
///
/// RLS guarantees tenant isolation: all queries are scoped to the
/// authenticated user's organization via JWT `app_metadata.org_id`.
class PostgresOperationalZoneRepository implements OperationalZoneRepository {
  final SupabaseClient _client;

  PostgresOperationalZoneRepository([SupabaseClient? client])
    : _client = client ?? supabase;

  @override
  Future<void> save(OperationalZone zone) async {
    await _client.from('operational_zones').upsert({
      'id': zone.id,
      'organization_id': zone.organizationId,
      'name': zone.name,
      'latitude': zone.latitude,
      'longitude': zone.longitude,
      'radius_meters': zone.radiusMeters,
    });
  }

  @override
  Future<OperationalZone?> findById(
    String id, {
    required String organizationId,
  }) async {
    final data = await _client
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
    final List<dynamic> data = await _client
        .from('operational_zones')
        .select()
        .eq('organization_id', organizationId)
        .order('name', ascending: true);

    return data.map((d) => _mapToEntity(d)).toList();
  }

  OperationalZone _mapToEntity(Map<String, dynamic> data) {
    return OperationalZone.reconstitute(
      id: data['id'],
      organizationId: data['organization_id'],
      name: data['name'],
      latitude: (data['latitude'] as num).toDouble(),
      longitude: (data['longitude'] as num).toDouble(),
      radiusMeters: data['radius_meters'] as int,
    );
  }
}
