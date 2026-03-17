import 'package:pactaflow/domain/entities/vehicle.dart';
import 'package:pactaflow/domain/enums/vehicle_status.dart';

abstract class IVehicleAssetRepository {
  Future<List<Vehicle>> getVehicles();
  Future<Vehicle> addVehicle({
    required String plate,
    String? model,
    required int capacity,
    VehicleStatus status,
  });
  Future<void> updateVehicle(Vehicle vehicle);
  Future<void> deleteVehicle(String vehicleId);
}
