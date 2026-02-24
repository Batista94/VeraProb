import '../../../domain/entities/operational_trip.dart';
import '../../../domain/entities/operational_warning.dart';
import '../../../domain/entities/trip_event.dart';
import '../../../domain/enums/trip_status.dart';
import 'situation_detector.dart';

/// Detects if a dispatched/enRoute vehicle is stopped for too long.
///
/// Rule:
/// - In simulation, speed is null (not measured) unless explicitly 0.
/// - Later this will check actual GPS positions timestamps.
/// - For now, if status is 'enRoute' but we haven't seen an update
///   or if a mock property detects stoppage, we flag it.
/// Since simulated speed isn't real, we mock the stoppage logic here
/// by looking at consecutive events or simply flagging 'interrupted' trips with high severity.
class StoppedVehicleDetector extends SituationDetector {
  const StoppedVehicleDetector()
    : super(id: 'stopped_vehicle', name: 'Detector de Veículo Parado');

  @override
  bool canDetect(OperationalTrip trip) {
    return trip.isActive;
  }

  @override
  OperationalWarning? evaluate(OperationalTrip trip, List<TripEvent> history) {
    // Basic heuristic: if the trip is interrupted, it's a severe stoppage
    if (trip.status == TripStatus.interrupted) {
      return OperationalWarning(
        id: 'warn_stopped_interrupted_${trip.id}',
        type: 'vehicle_stopped',
        message: 'Veículo Interrompido',
        severityScore: 50,
        detectedAt: DateTime.now(),
      );
    }

    // Future: Analyze position history to see if speed = 0 for > 5 mins
    return null;
  }
}
