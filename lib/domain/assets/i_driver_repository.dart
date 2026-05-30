// pr_scanner: ignore-regression
//
import 'package:veraprob/domain/entities/driver.dart';

/// Port for driver CRUD operations.
///
/// Concrete implementation: [PostgresDriverRepository].
/// INV-18: Pure Dart interface — zero infrastructure dependencies.
abstract class IDriverRepository {
  Future<List<Driver>> getDrivers();
  Future<void> addDriver(Driver driver);

  /// INV-3: Soft-archive via offboard_driver RPC. No hard DELETE.
  Future<void> archiveDriver(String id);
  Future<void> updateDriver(Driver driver);

  /// Bloco 1D: idempotent batch upsert from CSV import.
  ///
  /// [rows] are DB-shaped maps whose keys match the `batch_upsert_drivers`
  /// RPC recordset. Returns the number of affected rows (INV-16).
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  );
}
