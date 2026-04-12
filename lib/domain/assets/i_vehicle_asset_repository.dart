import 'package:veraprob/domain/entities/vehicle.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';

/// Port for vehicle asset CRUD operations.
///
/// Concrete implementation: [PostgresVehicleAssetRepository].
/// INV-18: Pure Dart interface — zero infrastructure dependencies.
abstract class IVehicleAssetRepository {
  Future<List<Vehicle>> getVehicles();
  Future<Vehicle> addVehicle({
    required String plate,
    String? model,
    required int capacity,
    VehicleStatus status,
  });

  /// Updates a vehicle with optimistic locking (INV-32).
  ///
  /// **Returns** the vehicle with the new `version` assigned by the database.
  /// The caller MUST use the returned instance for subsequent operations
  /// to avoid [ConflictException] from stale versions.
  Future<Vehicle> updateVehicle(Vehicle vehicle);
  Future<void> deleteVehicle(String vehicleId);
}
