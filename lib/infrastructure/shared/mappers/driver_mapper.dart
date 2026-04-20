import 'package:veraprob/domain/entities/driver.dart';

class DriverMapper {
  static Driver fromSupabase(Map<String, dynamic> data) {
    return Driver(
      id: data['id'] as String,
      organizationId: data['organization_id'] as String,
      name: data['full_name'] as String,
      licenseNumber: data['license_number'] as String,
      status: _parseStatus(data['status'] as String?),
    );
  }

  static Map<String, dynamic> toSupabase(Driver driver, String orgId) {
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
