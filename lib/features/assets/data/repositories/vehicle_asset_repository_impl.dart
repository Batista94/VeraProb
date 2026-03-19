import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/domain/entities/vehicle.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';
import 'vehicle_asset_repository.dart';

class VehicleAssetRepositoryImpl implements IVehicleAssetRepository {
  final SupabaseClient _supabase;

  VehicleAssetRepositoryImpl(this._supabase);

  String get _orgId {
    final orgId =
        _supabase.auth.currentSession?.user.appMetadata['org_id'] as String?;
    if (orgId == null) throw StateError('No organization in session JWT');
    return orgId;
  }

  @override
  Future<List<Vehicle>> getVehicles() async {
    final response = await _supabase
        .from('vehicles')
        .select()
        .order('plate', ascending: true);

    return (response as List)
        .map((row) => Vehicle.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<Vehicle> addVehicle({
    required String plate,
    String? model,
    required int capacity,
    VehicleStatus status = VehicleStatus.available,
  }) async {
    final response = await _supabase
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
  }

  @override
  Future<void> updateVehicle(Vehicle vehicle) async {
    await _supabase
        .from('vehicles')
        .update({
          'plate': vehicle.plate.toUpperCase().trim(),
          'model': vehicle.model?.trim(),
          'capacity': vehicle.capacity,
          'status': vehicle.status.dbValue,
        })
        .eq('id', vehicle.id);
  }

  @override
  Future<void> deleteVehicle(String vehicleId) async {
    await _supabase.from('vehicles').delete().eq('id', vehicleId);
  }
}
