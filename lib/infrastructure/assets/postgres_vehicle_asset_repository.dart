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
  ) async {
    try {
      final result = await client.rpc<dynamic>(
        'batch_upsert_vehicles',
        params: {'p_org_id': organizationId, 'p_rows': rows},
      );
      return (result as num).toInt();
    } on PostgrestException catch (e) {
      throw mapPostgrestToDomainException(e, resourceType: 'vehicle_asset');
    }
  }

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

  /// Batch update with atomic optimistic locking via Postgres RPC.
  ///
  /// If ANY vehicle has a stale version, the ENTIRE batch is rolled back
  /// by Postgres — zero partial commits possible.
  ///
  /// Returns the updated vehicles list (same order as input).
  Future<List<Vehicle>> batchUpdateVehicles(
    List<BatchUpdateSpec> updates,
  ) async {
    try {
      await batchUpdateWithVersion(
        rpcFunction: 'batch_update_vehicles',
        updates: updates,
      );

      // Re-fetch updated vehicles to return fresh state with new versions
      final ids = updates.map((u) => u.id).toList();
      final rows = await client.from('vehicles').select().inFilter('id', ids);
      return (rows as List)
          .map((row) => Vehicle.fromJson(row as Map<String, dynamic>))
          .toList();
    } on ConflictException {
      rethrow;
    } on PostgrestException catch (e) {
      // P0001 from batch RPC = conflict → convert to ConflictException
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

  /// Extracts vehicle IDs from a batch conflict error message.
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
