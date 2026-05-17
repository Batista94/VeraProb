import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/entities/driver.dart';
import 'package:veraprob/domain/assets/i_driver_repository.dart';
import 'package:veraprob/infrastructure/shared/mappers/driver_mapper.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase implementation of [IDriverRepository].
///
/// Wraps `SupabaseClient` so that no Widget ever imports
/// `supabase_flutter` directly (SRP-UI-LEAK prevention).
class PostgresDriverRepository extends BasePostgresRepository
    implements IDriverRepository {
  PostgresDriverRepository(super.client);

  String get _orgId {
    final orgId =
        client.auth.currentSession?.user.appMetadata['org_id'] as String?;
    if (orgId == null) throw StateError('No organization in session JWT');
    return orgId;
  }

  @override
  Future<List<Driver>> getDrivers() async {
    try {
      final response = await client
          .from('drivers')
          .select()
          .order('full_name', ascending: true);
      return (response as List).map((data) {
        return DriverMapper.fromSupabase(data);
      }).toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'driver');
    }
  }

  @override
  Future<void> addDriver(Driver driver) async {
    try {
      await client
          .from('drivers')
          .insert(DriverMapper.toSupabase(driver, _orgId));
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'driver');
    }
  }

  @override
  Future<void> archiveDriver(String driverId) async {
    try {
      // INV-3: No hard DELETE. RPC soft-archives driver + revokes Telegram bindings.
      await client.rpc<void>(
        'offboard_driver',
        params: {'p_driver_id': driverId, 'p_org_id': _orgId},
      );
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'driver');
    }
  }

  @override
  Future<void> updateDriver(Driver driver) async {
    try {
      await client
          .from('drivers')
          .update(DriverMapper.toSupabase(driver, _orgId))
          .eq('id', driver.id);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'driver');
    }
  }
}
