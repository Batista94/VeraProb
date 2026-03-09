import 'package:flutter/material.dart';
import '../../domain/enums/trip_status.dart';
import '../../domain/enums/event_type.dart';
import '../../domain/entities/operational_suggestion.dart';

/// Presentation-layer UI mappings for [TripStatus].
///
/// Kept separate from the domain enum to preserve Domain Sovereignty —
/// the domain must remain pure Dart with no Flutter dependencies.
extension TripStatusUi on TripStatus {
  Color get color {
    switch (this) {
      case TripStatus.scheduled:
        return const Color(0xFF448AFF);
      case TripStatus.dispatched:
        return const Color(0xFFFFD600);
      case TripStatus.enRoute:
        return const Color(0xFF00C853);
      case TripStatus.atStop:
        return const Color(0xFF00C853);
      case TripStatus.delayed:
        return const Color(0xFFFF9100);
      case TripStatus.interrupted:
        return const Color(0xFFFF1744);
      case TripStatus.completed:
        return const Color(0xFF78909C);
      case TripStatus.cancelled:
        return const Color(0xFF37474F);
      case TripStatus.noShow:
        return const Color(0xFFB71C1C);
      case TripStatus.offline:
        return const Color(0xFF9E9E9E);
      case TripStatus.maintenance:
        return const Color(0xFF212121);
      case TripStatus.detour:
        return const Color(0xFFFF6D00);
    }
  }

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
}

/// Presentation-layer UI mappings for [EventType].
extension EventTypeUi on EventType {
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
}

/// Presentation-layer icon mapping for [SuggestionAction].
///
/// The callback (onExecute) is intentionally NOT here — it is wired
/// directly in the widget that owns the [WidgetRef] and [tripId],
/// keeping this extension free of Riverpod dependencies.
extension SuggestionActionUi on SuggestionAction {
  IconData get icon {
    switch (this) {
      case SuggestionAction.cancelTrip:
        return Icons.cancel_outlined;
      case SuggestionAction.interruptTrip:
        return Icons.pause_circle_outline;
      case SuggestionAction.regularizeTrip:
        return Icons.check_circle_outline;
    }
  }
}
