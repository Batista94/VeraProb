import 'package:flutter/material.dart';

import '../../../domain/enums/vehicle_status.dart';

/// Presentation-layer mapper for [VehicleStatus] UI properties.
///
/// Keeps Flutter/Material dependencies out of the domain layer (INV-4).
/// Call sites that previously used [VehicleStatus.color] and [VehicleStatus.icon]
/// must go through this mapper instead.
class VehicleStatusUiMapper {
  const VehicleStatusUiMapper._();

  static Color colorFor(VehicleStatus status) {
    switch (status) {
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

  static IconData iconFor(VehicleStatus status) {
    switch (status) {
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
}
