import '../../../application/operational_control_service.dart';
import '../../../domain/entities/operational_trip.dart';
import '../../../domain/entities/operational_warning.dart';
import 'detectors/delay_detector.dart';
import 'detectors/situation_detector.dart';
import 'detectors/stopped_vehicle_detector.dart';

/// The core intelligence engine that analyzes active trips and detects issues.
///
/// In Sprint 3, this operates as a pure transformer function that takes raw
/// trips from the data layer and enhances them with [OperationalWarning]s and
/// a total `severityScore`.
class SituationEngine {
  final List<SituationDetector> _detectors = [
    const DelayDetector(),
    const StoppedVehicleDetector(),
  ];

  /// Analyzes a list of trips and returns a new list enriched with intelligence.
  List<OperationalTrip> analyze(
    List<OperationalTrip> rawTrips,
    OperationalControlService control,
  ) {
    return rawTrips.map((trip) {
      if (!trip.isActive) return trip; // Terminal trips don't need analysis

      final history = control.getEventsForTrip(trip.id);
      final warnings = <OperationalWarning>[];
      int totalSeverity = 0;

      // Run each detector
      for (final detector in _detectors) {
        if (detector.canDetect(trip)) {
          final warning = detector.evaluate(trip, history);
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
