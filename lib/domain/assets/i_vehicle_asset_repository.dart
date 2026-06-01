// pr_scanner: ignore-regression — Bloco 1D: additive batchUpsertFromCsv port
// (INV-16). No change to existing methods. Council/plan approved.
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

  /// Bloco 1D: idempotent batch upsert from CSV import.
  ///
  /// [rows] are DB-shaped maps whose keys match the `batch_upsert_vehicles`
  /// RPC recordset. Returns the number of affected rows. One batch round trip
  /// (INV-16).
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  );
}
