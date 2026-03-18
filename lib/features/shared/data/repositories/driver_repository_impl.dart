import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/entities/driver.dart';
import 'driver_repository.dart';

class DriverRepositoryImpl implements IDriverRepository {
  final SupabaseClient _supabase;

  DriverRepositoryImpl(this._supabase);

  String get _orgId {
    final orgId =
        _supabase.auth.currentSession?.user.appMetadata['org_id'] as String?;
    if (orgId == null) throw StateError('No organization in session JWT');
    return orgId;
  }

  @override
  Future<List<Driver>> getDrivers() async {
    final response = await _supabase
        .from('drivers')
        .select()
        .order('full_name', ascending: true);

    return (response as List).map((data) {
      return Driver(
        id: data['id'] as String,
        organizationId: data['organization_id'] as String,
        name: data['full_name'] as String,
        licenseNumber: data['license_number'] as String,
        status: _parseStatus(data['status'] as String?),
      );
    }).toList();
  }

  @override
  Future<void> addDriver(Driver driver) async {
    await _supabase.from('drivers').insert({
      'organization_id': _orgId,
      'full_name': driver.name,
      'license_number': driver.licenseNumber,
      'status': driver.status.name,
    });
  }

  @override
  Future<void> deleteDriver(String driverId) async {
    await _supabase.from('drivers').delete().eq('id', driverId);
  }

  @override
  Future<void> updateDriver(Driver driver) async {
    await _supabase
        .from('drivers')
        .update({
          'full_name': driver.name,
          'license_number': driver.licenseNumber,
          'status': driver.status.name,
        })
        .eq('id', driver.id);
  }

  DriverStatus _parseStatus(String? value) {
    return switch (value) {
      'inactive' => DriverStatus.inactive,
      'pending' => DriverStatus.pending,
      _ => DriverStatus.active,
    };
  }
}
