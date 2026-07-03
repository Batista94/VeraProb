import 'package:flutter/material.dart';
import 'package:veraprob/core/theme/app_theme.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/application/normalization/models/trip_status_view.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/entities/operational_suggestion.dart';

/// Presentation-layer UI mappings for [TripStatus].
///
/// Kept separate from the domain enum to preserve Domain Sovereignty —
/// the domain must remain pure Dart with no Flutter dependencies.
extension TripStatusUi on TripStatus {
  Color get color {
    switch (this) {
      case TripStatus.scheduled:
        return VeraProbColors.info;
      case TripStatus.dispatched:
        return VeraProbColors.warning;
      case TripStatus.enRoute:
        return VeraProbColors.success;
      case TripStatus.atStop:
        return VeraProbColors.success;
      case TripStatus.delayed:
        return VeraProbColors.warning;
      case TripStatus.interrupted:
        return VeraProbColors.error;
      case TripStatus.completed:
        return VeraProbColors.neutral;
      case TripStatus.cancelled:
        return VeraProbColors.textDisabled;
      case TripStatus.noShow:
        return VeraProbColors.error;
      case TripStatus.offline:
        return VeraProbColors.neutral;
      case TripStatus.maintenance:
        return VeraProbColors.background;
      case TripStatus.detour:
        return VeraProbColors.warning;
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

extension TripStatusViewUi on TripStatusView {
  Color get color {
    switch (this) {
      case TripStatusView.scheduled:
        return VeraProbColors.info;
      case TripStatusView.enRoute:
        return VeraProbColors.success;
      case TripStatusView.atStop:
        return VeraProbColors.success;
      case TripStatusView.delayed:
        return VeraProbColors.warning;
      case TripStatusView.interrupted:
        return VeraProbColors.error;
      case TripStatusView.completed:
        return VeraProbColors.neutral;
      case TripStatusView.cancelled:
        return VeraProbColors.textDisabled;
      case TripStatusView.noShow:
        return VeraProbColors.error;
      case TripStatusView.maintenance:
        return VeraProbColors.background;
    }
  }

  IconData get icon {
    switch (this) {
      case TripStatusView.scheduled:
        return Icons.schedule;
      case TripStatusView.enRoute:
        return Icons.directions_bus;
      case TripStatusView.atStop:
        return Icons.hail;
      case TripStatusView.delayed:
        return Icons.warning_amber_rounded;
      case TripStatusView.interrupted:
        return Icons.error;
      case TripStatusView.completed:
        return Icons.check_circle;
      case TripStatusView.cancelled:
        return Icons.cancel;
      case TripStatusView.noShow:
        return Icons.remove_circle;
      case TripStatusView.maintenance:
        return Icons.build;
    }
  }
}
