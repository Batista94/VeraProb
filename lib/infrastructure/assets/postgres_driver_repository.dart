import 'package:veraprob/domain/entities/driver.dart';
import 'package:veraprob/domain/assets/i_driver_repository.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase implementation of [IDriverRepository].
///
/// Wraps `SupabaseClient` so that no Widget ever imports
/// `supabase_flutter` directly (SRP-UI-LEAK prevention).
class PostgresDriverRepository extends BasePostgresRepository
    implements IDriverRepository {
  PostgresDriverRepository(super.client);

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) {
    return withErrorHandler(
      'driver',
      null,
      () => executeBatchUpsertInChunks(
        rpcFunction: 'batch_upsert_drivers',
        organizationId: organizationId,
        rows: rows,
      ),
    );
  }

  @override
  Future<List<Driver>> getDrivers() {
    return withErrorHandler('driver', null, () async {
      final response = await client
          .from('drivers')
          .select()
          .order('full_name', ascending: true);
      return (response as List)
          .map((data) => _fromSupabase(data as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<void> addDriver(Driver driver) {
    return withErrorHandler(
      'driver',
      driver.id,
      () => client.from('drivers').insert(_toSupabase(driver, sessionOrgId)),
    );
  }

  @override
  Future<void> archiveDriver(String driverId) {
    return withErrorHandler(
      'driver',
      driverId,
      () => client.rpc<void>(
        'offboard_driver',
        params: {'p_driver_id': driverId, 'p_org_id': sessionOrgId},
      ),
    );
  }

  @override
  Future<void> updateDriver(Driver driver) {
    return withErrorHandler(
      'driver',
      driver.id,
      () => client
          .from('drivers')
          .update(_toSupabase(driver, sessionOrgId))
          .eq('id', driver.id),
    );
  }

  static Driver _fromSupabase(Map<String, dynamic> data) {
    final archivedRaw = data['archived_at_utc'] as String?;
    return Driver(
      id: data['id'] as String,
      organizationId: data['organization_id'] as String,
      name: data['full_name'] as String,
      licenseNumber: data['license_number'] as String,
      status: _parseStatus(data['status'] as String?),
      archivedAtUtc: archivedRaw != null
          ? DateTime.parse(archivedRaw).toUtc()
          : null,
    );
  }

  static Map<String, dynamic> _toSupabase(Driver driver, String orgId) {
    return {
      'organization_id': orgId,
      'full_name': driver.name,
      'license_number': driver.licenseNumber,
      'status': driver.status.name,
    };
  }

  static DriverStatus _parseStatus(String? value) {
    return switch (value) {
      'inactive' => DriverStatus.inactive,
      'pending' => DriverStatus.pending,
      _ => DriverStatus.active,
    };
  }
}
