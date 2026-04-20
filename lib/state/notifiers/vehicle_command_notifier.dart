import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/domain/entities/vehicle.dart';
import 'package:veraprob/domain/enums/vehicle_status.dart';
import 'package:veraprob/features/admin/providers/vehicles_provider.dart';
import 'package:veraprob/infrastructure/assets/postgres_vehicle_asset_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/infrastructure/shared/base_postgres_repository.dart';

/// Exposes [PostgresVehicleAssetRepository] typed as its concrete class
/// so that the [VehicleCommandNotifier] can access batch operations.
///
/// This provider is intentionally NOT typed as [IVehicleAssetRepository]
/// because the batch update API is specific to the Postgres implementation
/// and is required for atomic fleet mutations (INV-32).
final postgresVehicleAssetRepositoryProvider =
    Provider<PostgresVehicleAssetRepository>((ref) {
      return PostgresVehicleAssetRepository(ref.read(supabaseClientProvider));
    });

/// Notifier that executes vehicle mutations (add, update, delete, batch)
/// and **automatically** invalidates fleet cache — preventing the "UI pipoco"
/// (stale state after mutation).
///
/// **Anti-Pipoco Strategy:**
/// After any mutation succeeds, this Notifier invalidates:
/// - [vehiclesListProvider] — the full vehicle list
///
/// Widgets watching [vehiclesListProvider] or [filteredVehiclesProvider]
/// will re-fetch automatically — no manual `ref.refresh` or
/// `ref.invalidate` needed in the widget layer.
///
/// **Usage:**
/// ```dart
/// final notifier = ref.read(vehicleCommandNotifierProvider);
/// final updated = await notifier.updateVehicle(vehicle);
/// // List is already refreshing — no ref.invalidate needed!
/// ```
class VehicleCommandNotifier extends AutoDisposeNotifier<void> {
  @override
  void build() {
    // This Notifier has no state — it's a pure command dispatcher.
    // The void return type is intentional: callers get the result
    // directly from the method return value, not from Notifier state.
  }

  /// Adds a vehicle and invalidates the fleet cache.
  Future<Vehicle> addVehicle({
    required String plate,
    String? model,
    required int capacity,
    VehicleStatus status = VehicleStatus.available,
  }) async {
    final repo = ref.read(postgresVehicleAssetRepositoryProvider);
    final vehicle = await repo.addVehicle(
      plate: plate,
      model: model,
      capacity: capacity,
      status: status,
    );
    ref.invalidate(vehiclesListProvider);
    return vehicle;
  }

  /// Updates a single vehicle with optimistic locking (INV-32).
  ///
  /// If a [ConflictException] is thrown, it propagates to the caller —
  /// the fleet cache is NOT invalidated on failure.
  Future<Vehicle> updateVehicle(Vehicle vehicle) async {
    final repo = ref.read(postgresVehicleAssetRepositoryProvider);
    final updated = await repo.updateVehicle(vehicle);
    ref.invalidate(vehiclesListProvider);
    return updated;
  }

  /// Deletes a vehicle and invalidates the fleet cache.
  Future<void> deleteVehicle(String vehicleId) async {
    final repo = ref.read(postgresVehicleAssetRepositoryProvider);
    await repo.deleteVehicle(vehicleId);
    ref.invalidate(vehiclesListProvider);
  }

  /// Batch updates vehicles with **atomic** optimistic locking (INV-32).
  ///
  /// If ANY vehicle has a stale version, the ENTIRE batch is rolled back
  /// by Postgres — zero partial commits. The [ConflictException] propagates
  /// to the caller and the fleet cache is NOT invalidated.
  ///
  /// Returns the updated vehicles list on success.
  Future<List<Vehicle>> batchUpdateVehicles(
    List<BatchUpdateSpec> updates,
  ) async {
    final repo = ref.read(postgresVehicleAssetRepositoryProvider);
    final updated = await repo.batchUpdateVehicles(updates);
    ref.invalidate(vehiclesListProvider);
    return updated;
  }
}

/// Provider for the [VehicleCommandNotifier].
///
/// Example:
/// ```dart
/// final notifier = ref.read(vehicleCommandNotifierProvider);
///
/// // Single update
/// final updated = await notifier.updateVehicle(vehicle);
///
/// // Batch update (atomic — rollback on any conflict)
/// final results = await notifier.batchUpdateVehicles(updates);
/// ```
final vehicleCommandNotifierProvider =
    AutoDisposeNotifierProvider<VehicleCommandNotifier, void>(
      VehicleCommandNotifier.new,
    );
