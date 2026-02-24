import 'package:flutter/material.dart';

/// Types of operational events logged for audit purposes.
enum EventType {
  statusChange,
  delayDetected,
  delayRecovered,
  positionLost,
  positionRestored,
  driverAssigned,
  vehicleAssigned,
  feedDisconnected,
  feedReconnected,
  manualOverride;

  String get label {
    switch (this) {
      case EventType.statusChange:
        return 'Mudança de Status';
      case EventType.delayDetected:
        return 'Atraso Detectado';
      case EventType.delayRecovered:
        return 'Atraso Recuperado';
      case EventType.positionLost:
        return 'Posição Perdida';
      case EventType.positionRestored:
        return 'Posição Restaurada';
      case EventType.driverAssigned:
        return 'Motorista Alocado';
      case EventType.vehicleAssigned:
        return 'Veículo Alocado';
      case EventType.feedDisconnected:
        return 'Feed Desconectado';
      case EventType.feedReconnected:
        return 'Feed Reconectado';
      case EventType.manualOverride:
        return 'Alteração Manual';
    }
  }

  IconData get icon {
    switch (this) {
      case EventType.statusChange:
        return Icons.swap_horiz;
      case EventType.delayDetected:
        return Icons.timer_off;
      case EventType.delayRecovered:
        return Icons.timer;
      case EventType.positionLost:
        return Icons.gps_off;
      case EventType.positionRestored:
        return Icons.gps_fixed;
      case EventType.driverAssigned:
        return Icons.person_add;
      case EventType.vehicleAssigned:
        return Icons.directions_bus;
      case EventType.feedDisconnected:
        return Icons.cloud_off;
      case EventType.feedReconnected:
        return Icons.cloud_done;
      case EventType.manualOverride:
        return Icons.edit;
    }
  }

  /// Severity level for visual treatment
  EventSeverity get severity {
    switch (this) {
      case EventType.delayDetected:
      case EventType.positionLost:
      case EventType.feedDisconnected:
        return EventSeverity.warning;
      case EventType.delayRecovered:
      case EventType.positionRestored:
      case EventType.feedReconnected:
        return EventSeverity.info;
      case EventType.statusChange:
      case EventType.driverAssigned:
      case EventType.vehicleAssigned:
      case EventType.manualOverride:
        return EventSeverity.neutral;
    }
  }

  static EventType fromString(String value) {
    switch (value) {
      case 'status_change':
        return EventType.statusChange;
      case 'delay_detected':
        return EventType.delayDetected;
      case 'delay_recovered':
        return EventType.delayRecovered;
      case 'position_lost':
        return EventType.positionLost;
      case 'position_restored':
        return EventType.positionRestored;
      case 'driver_assigned':
        return EventType.driverAssigned;
      case 'vehicle_assigned':
        return EventType.vehicleAssigned;
      case 'feed_disconnected':
        return EventType.feedDisconnected;
      case 'feed_reconnected':
        return EventType.feedReconnected;
      case 'manual_override':
        return EventType.manualOverride;
      default:
        return EventType.statusChange;
    }
  }

  String get dbValue {
    return name.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (m) => '_${m.group(0)!.toLowerCase()}',
    );
  }
}

enum EventSeverity { neutral, info, warning }
