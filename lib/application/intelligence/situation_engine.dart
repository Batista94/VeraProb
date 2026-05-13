import 'package:veraprob/application/operational_control_service.dart';
import 'package:veraprob/domain/shared/date_time_provider.dart';
import 'package:veraprob/domain/entities/operational_warning.dart';
import 'detectors/delay_detector.dart';
import 'detectors/off_route_detector.dart';
import 'detectors/signal_loss_detector.dart';
import 'detectors/situation_detector.dart';
import 'detectors/stopped_vehicle_detector.dart';

import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';

/// The core intelligence engine that analyzes active trips and detects issues.
///
/// In Sprint 3, this operates as a pure transformer function that takes raw
/// trips from the data layer and enhances them with [OperationalWarning]s and
/// a total `severityScore`.
class SituationEngine {
  final IDateTimeProvider _dateTimeProvider;

  SituationEngine(this._dateTimeProvider);

  List<SituationDetector> get _detectors => [
    DelayDetector(_dateTimeProvider),
    StoppedVehicleDetector(_dateTimeProvider),
    OffRouteDetector(_dateTimeProvider),
    SignalLossDetector(_dateTimeProvider),
  ];

  /// Analyzes a list of trips and returns a new list enriched with intelligence.
  List<OperationalTrip> analyze(
    List<OperationalTrip> rawTrips,
    Map<String, VehicleOperationalState> vehicleStates,
    OperationalControlService control,
  ) {
    return rawTrips.map((trip) {
      if (!trip.isActive) return trip; // Terminal trips don't need analysis

      final history = control.getEventsForTrip(trip.id);
      final state = vehicleStates[trip.vehicleId ?? trip.id];
      final warnings = <OperationalWarning>[];
      int totalSeverity = 0;

      // Run each detector
      for (final detector in _detectors) {
        if (detector.canDetect(trip)) {
          final warning = detector.evaluate(trip, state, history);
          if (warning != null) {
            warnings.add(warning);
            totalSeverity += warning.severityScore;
          }
        }
      }

      // Cap severity at 100
      final cappedSeverity = totalSeverity > 100 ? 100 : totalSeverity;

      return trip.copyWith(severityScore: cappedSeverity, warnings: warnings);
    }).toList();
  }
}
