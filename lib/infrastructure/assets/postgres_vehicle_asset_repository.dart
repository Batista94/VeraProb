import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/entities/vehicle.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';
import 'package:veraprob/domain/assets/i_vehicle_asset_repository.dart';
import 'package:veraprob/domain/shared/conflict_exception.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Supabase implementation of [IVehicleAssetRepository].
///
/// Wraps `SupabaseClient` so that no Widget ever imports
/// `supabase_flutter` directly (SRP-UI-LEAK prevention).
class PostgresVehicleAssetRepository extends BasePostgresRepository
    implements IVehicleAssetRepository {
  PostgresVehicleAssetRepository(super.client);

  String get _orgId {
    final orgId =
        client.auth.currentSession?.user.appMetadata['org_id'] as String?;
    if (orgId == null) throw StateError('No organization in session JWT');
    return orgId;
  }

  @override
  Future<List<Vehicle>> getVehicles() async {
    try {
      final response = await client
          .from('vehicles')
          .select()
          .order('plate', ascending: true);
      return (response as List)
          .map((row) => Vehicle.fromJson(row as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'vehicle_asset');
    }
  }

  @override
  Future<Vehicle> addVehicle({
    required String plate,
    String? model,
    required int capacity,
    VehicleStatus status = VehicleStatus.available,
  }) async {
    try {
      final response = await client
          .from('vehicles')
          .insert({
            'organization_id': _orgId,
            'plate': plate.toUpperCase().trim(),
            'model': model?.trim(),
            'capacity': capacity,
            'status': status.dbValue,
          })
          .select()
          .single();
      return Vehicle.fromJson(response);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'vehicle_asset');
    }
  }

  @override
  Future<Vehicle> updateVehicle(Vehicle vehicle) async {
    try {
      final newVersion = await updateWithVersion(
        table: 'vehicles',
        data: {
          'plate': vehicle.plate.toUpperCase().trim(),
          'model': vehicle.model?.trim(),
          'capacity': vehicle.capacity,
          'status': vehicle.status.dbValue,
        },
        id: vehicle.id,
        currentVersion: vehicle.version,
        resourceType: 'vehicle',
      );
      // Vehicle has copyWith — return updated entity with new version.
      return vehicle.copyWith(version: newVersion);
    } on ConflictException {
      rethrow; // Already typed — propagate directly (INV-10)
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'vehicle_asset');
    }
  }

  @override
  Future<void> deleteVehicle(String vehicleId) async {
    try {
      await client.from('vehicles').delete().eq('id', vehicleId);
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'vehicle_asset');
    }
  }
}
