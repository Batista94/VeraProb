/// Operational status of a vehicle in the fleet.
enum VehicleStatus {
  available,
  inService,
  maintenance,
  retired;

  String get label {
    switch (this) {
      case VehicleStatus.available:
        return 'Disponível';
      case VehicleStatus.inService:
        return 'Em Serviço';
      case VehicleStatus.maintenance:
        return 'Manutenção';
      case VehicleStatus.retired:
        return 'Aposentado';
    }
  }

  static VehicleStatus fromString(String value) {
    switch (value) {
      case 'available':
        return VehicleStatus.available;
      case 'in_service':
        return VehicleStatus.inService;
      case 'maintenance':
        return VehicleStatus.maintenance;
      case 'retired':
        return VehicleStatus.retired;
      default:
        return VehicleStatus.available;
    }
  }

  String get dbValue {
    switch (this) {
      case VehicleStatus.inService:
        return 'in_service';
      default:
        return name;
    }
  }
}
