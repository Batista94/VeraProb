import 'package:flutter/material.dart';

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

  Color get color {
    switch (this) {
      case VehicleStatus.available:
        return const Color(0xFF00C853);
      case VehicleStatus.inService:
        return const Color(0xFF448AFF);
      case VehicleStatus.maintenance:
        return const Color(0xFFFF9100);
      case VehicleStatus.retired:
        return const Color(0xFF78909C);
    }
  }

  IconData get icon {
    switch (this) {
      case VehicleStatus.available:
        return Icons.check_circle_outline;
      case VehicleStatus.inService:
        return Icons.directions_bus;
      case VehicleStatus.maintenance:
        return Icons.build;
      case VehicleStatus.retired:
        return Icons.block;
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
