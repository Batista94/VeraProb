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

  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) {
    return withErrorHandler(
      'vehicle_asset',
      null,
      () => executeBatchUpsertInChunks(
        rpcFunction: 'batch_upsert_vehicles',
        organizationId: organizationId,
        rows: rows,
      ),
    );
  }

  @override
  Future<List<Vehicle>> getVehicles() {
    return withErrorHandler('vehicle_asset', null, () async {
      final response = await client
          .from('vehicles')
          .select()
          .order('plate', ascending: true);
      return (response as List)
          .map((row) => Vehicle.fromJson(row as Map<String, dynamic>))
          .toList();
    });
  }

  @override
  Future<Vehicle> addVehicle({
    required String plate,
    String? model,
    required int capacity,
    VehicleStatus status = VehicleStatus.available,
  }) {
    return withErrorHandler('vehicle_asset', null, () async {
      final response = await client
          .from('vehicles')
          .insert({
            'organization_id': sessionOrgId,
            'plate': plate.toUpperCase().trim(),
            'model': model?.trim(),
            'capacity': capacity,
            'status': status.dbValue,
          })
          .select()
          .single();
      return Vehicle.fromJson(response);
    });
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
      return vehicle.copyWith(version: newVersion);
    } on ConflictException {
      rethrow;
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'vehicle_asset');
    }
  }

  @override
  Future<void> deleteVehicle(String vehicleId) {
    return withErrorHandler(
      'vehicle_asset',
      vehicleId,
      () => client.from('vehicles').delete().eq('id', vehicleId),
    );
  }

  /// Batch update with atomic optimistic locking via Postgres RPC.
  ///
  /// If ANY vehicle has a stale version, the ENTIRE batch is rolled back
  /// by Postgres — zero partial commits possible.
  Future<List<Vehicle>> batchUpdateVehicles(
    List<BatchUpdateSpec> updates,
  ) async {
    try {
      await batchUpdateWithVersion(
        rpcFunction: 'batch_update_vehicles',
        updates: updates,
      );

      final ids = updates.map((u) => u.id).toList();
      final rows = await client.from('vehicles').select().inFilter('id', ids);
      return (rows as List)
          .map((row) => Vehicle.fromJson(row as Map<String, dynamic>))
          .toList();
    } on ConflictException {
      rethrow;
    } on PostgrestException catch (e) {
      if (e.message.contains('Batch conflict') || e.message.contains('P0001')) {
        final staleIds = _extractBatchStaleIds(e.message);
        throw ConflictException.staleVersion(
          resourceType: 'batch',
          resourceId: staleIds.join(', '),
          clientVersion: -1,
          currentVersion: -1,
        );
      }
      throw mapPostgrestToDomainException(e, resourceType: 'vehicle_asset');
    }
  }

  List<String> _extractBatchStaleIds(String message) {
    final ids = <String>[];
    final matches = RegExp(
      r'vehicle\s+([a-f0-9-]+)',
    ).allMatches(message.toLowerCase());
    for (final match in matches) {
      if (match.groupCount >= 1) ids.add(match.group(1)!);
    }
    return ids.isEmpty ? ['unknown'] : ids;
  }
}
