import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/admin/i_active_vehicle_repository.dart';
import 'package:veraprob/infrastructure/shared/postgres_error_interceptor.dart';

/// PostgreSQL implementation of [IActiveVehicleRepository] via Supabase.
///
/// Queries the `vehicles` table (introduced in Bloco 8 — Asset Manager,
/// migration 20260322000002_vehicles_table.sql).
///
/// RLS on `vehicles` enforces org isolation via `app_metadata.org_id` (INV-10).
///
/// Uses postgrest's native `.count()` terminator — only the Content-Range
/// header is returned; zero rows are transmitted over the network.
class PostgresActiveVehicleRepository
    with PostgresErrorInterceptor
    implements IActiveVehicleRepository {
  final SupabaseClient _client;

  const PostgresActiveVehicleRepository(this._client);

  @override
  Future<int> countActiveByOrganization(String organizationId) async {
    try {
      return await _client
          .from('vehicles')
          .count()
          .eq('organization_id', organizationId)
          .eq('status', 'active');
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'active_vehicle');
    }
  }
}
