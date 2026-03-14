import '../../../domain/entities/operational_trip.dart';
import '../../../domain/entities/operational_warning.dart';
import '../../../domain/entities/trip_event.dart';
import '../../../domain/enums/trip_status.dart';
import '../../../domain/entities/vehicle_operational_state.dart';
import 'situation_detector.dart';

/// Detects if a trip is delayed beyond acceptable thresholds.
///
/// Rule:
/// - Delay > 10 min: Critical Delay (Score: 40)
/// - Delay > 3 min: Risk of Delay (Score: 20)
class DelayDetector extends SituationDetector {
  const DelayDetector()
    : super(id: 'delay_detector', name: 'Detector de Atraso');

  @override
  bool canDetect(OperationalTrip trip) {
    // Only check active trips that are not cancelled or completed
    return trip.isActive || trip.status == TripStatus.scheduled;
  }

  @override
  OperationalWarning? evaluate(
    OperationalTrip trip,
    VehicleOperationalState? state,
    List<TripEvent> history,
  ) {
    final delayMinutes = trip.delaySeconds ~/ 60;

    if (delayMinutes >= 10) {
      return OperationalWarning(
        id: 'warn_delay_critical_${trip.id}',
        type: 'delay_critical',
        message: 'Atraso Crítico: $delayMinutes min',
        severityScore: 40,
        detectedAt: DateTime.now().toUtc(),
        metadata: {'delay_minutes': delayMinutes},
      );
    }

    if (delayMinutes >= 3) {
      return OperationalWarning(
        id: 'warn_delay_risk_${trip.id}',
        type: 'delay_risk',
        message: 'Risco de Atraso: $delayMinutes min',
        severityScore: 20,
        detectedAt: DateTime.now().toUtc(),
        metadata: {'delay_minutes': delayMinutes},
      );
    }

    return null; // No significant delay
  }
}
