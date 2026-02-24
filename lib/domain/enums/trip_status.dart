import 'package:flutter/material.dart';

/// Operational states of a trip in the BusFlow control center.
///
/// These states form a finite state machine that drives all operational
/// visualizations — map marker colors, KPI bars, alert evaluation, and
/// timeline rendering.
enum TripStatus {
  /// Trip is programmed (from GTFS schedule or manual entry)
  scheduled,

  /// Driver + vehicle assigned, awaiting departure
  dispatched,

  /// Vehicle detected in motion along route
  enRoute,

  /// Vehicle stopped at a scheduled stop
  atStop,

  /// Delay exceeds configured threshold
  delayed,

  /// Unplanned stop or emergency
  interrupted,

  /// Trip reached final destination
  completed,

  /// Trip cancelled before or during execution
  cancelled,

  /// Scheduled trip never started
  noShow,

  /// Signals lost from the vehicle for more than threshold
  offline,

  /// Vehicle suffered a mechanical failure
  maintenance,

  /// Vehicle is manually overridden into an alternative active route
  detour;

  /// Display label in Portuguese for operators
  String get label {
    switch (this) {
      case TripStatus.scheduled:
        return 'Programada';
      case TripStatus.dispatched:
        return 'Despachada';
      case TripStatus.enRoute:
        return 'Em Trânsito';
      case TripStatus.atStop:
        return 'No Ponto';
      case TripStatus.delayed:
        return 'Atrasada';
      case TripStatus.interrupted:
        return 'Interrompida';
      case TripStatus.completed:
        return 'Completada';
      case TripStatus.cancelled:
        return 'Cancelada';
      case TripStatus.noShow:
        return 'Não Iniciada';
      case TripStatus.offline:
        return 'Sem Sinal';
      case TripStatus.maintenance:
        return 'Fora de Serviço';
      case TripStatus.detour:
        return 'Desvio Ativo';
    }
  }

  /// Map marker and badge color for this status
  Color get color {
    switch (this) {
      case TripStatus.scheduled:
        return const Color(0xFF448AFF); // Blue
      case TripStatus.dispatched:
        return const Color(0xFFFFD600); // Yellow
      case TripStatus.enRoute:
        return const Color(0xFF00C853); // Green
      case TripStatus.atStop:
        return const Color(0xFF00C853); // Green (pulsing in UI)
      case TripStatus.delayed:
        return const Color(0xFFFF9100); // Amber
      case TripStatus.interrupted:
        return const Color(0xFFFF1744); // Red
      case TripStatus.completed:
        return const Color(0xFF78909C); // Gray
      case TripStatus.cancelled:
        return const Color(0xFF37474F); // Dark gray
      case TripStatus.noShow:
        return const Color(0xFFB71C1C); // Dark red
      case TripStatus.offline:
        return const Color(0xFF9E9E9E); // Grey
      case TripStatus.maintenance:
        return const Color(0xFF212121); // Almost Black
      case TripStatus.detour:
        return const Color(0xFFFF6D00); // Deep Orange
    }
  }

  /// Icon for this status
  IconData get icon {
    switch (this) {
      case TripStatus.scheduled:
        return Icons.schedule;
      case TripStatus.dispatched:
        return Icons.assignment_turned_in;
      case TripStatus.enRoute:
        return Icons.directions_bus;
      case TripStatus.atStop:
        return Icons.hail;
      case TripStatus.delayed:
        return Icons.warning_amber_rounded;
      case TripStatus.interrupted:
        return Icons.error;
      case TripStatus.completed:
        return Icons.check_circle;
      case TripStatus.cancelled:
        return Icons.cancel;
      case TripStatus.noShow:
        return Icons.remove_circle;
      case TripStatus.offline:
        return Icons.portable_wifi_off;
      case TripStatus.maintenance:
        return Icons.build;
      case TripStatus.detour:
        return Icons.alt_route;
    }
  }

  /// Whether this status represents an active (in-progress) trip
  bool get isActive {
    switch (this) {
      case TripStatus.enRoute:
      case TripStatus.atStop:
      case TripStatus.delayed:
      case TripStatus.interrupted:
      case TripStatus.detour:
      case TripStatus.offline: // it's active but bleeding
        return true;
      default:
        return false;
    }
  }

  /// Whether this status should trigger operator attention
  bool get requiresAttention {
    switch (this) {
      case TripStatus.delayed:
      case TripStatus.interrupted:
      case TripStatus.noShow:
      case TripStatus.offline:
      case TripStatus.maintenance:
        return true;
      default:
        return false;
    }
  }

  /// Whether this is a terminal state (trip is finished)
  bool get isTerminal {
    switch (this) {
      case TripStatus.completed:
      case TripStatus.cancelled:
      case TripStatus.noShow:
      case TripStatus.maintenance:
        return true;
      default:
        return false;
    }
  }

  /// Parse from database string value
  static TripStatus fromString(String value) {
    switch (value) {
      case 'scheduled':
        return TripStatus.scheduled;
      case 'dispatched':
        return TripStatus.dispatched;
      case 'en_route':
        return TripStatus.enRoute;
      case 'at_stop':
        return TripStatus.atStop;
      case 'delayed':
        return TripStatus.delayed;
      case 'interrupted':
        return TripStatus.interrupted;
      case 'completed':
        return TripStatus.completed;
      case 'cancelled':
        return TripStatus.cancelled;
      case 'no_show':
        return TripStatus.noShow;
      default:
        return TripStatus.scheduled;
    }
  }

  /// Database string representation (snake_case)
  String get dbValue {
    switch (this) {
      case TripStatus.enRoute:
        return 'en_route';
      case TripStatus.atStop:
        return 'at_stop';
      case TripStatus.noShow:
        return 'no_show';
      default:
        return name;
    }
  }
}
