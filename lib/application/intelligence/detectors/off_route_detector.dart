import '../../../domain/entities/operational_trip.dart';
import '../../../domain/entities/operational_warning.dart';
import '../../../domain/entities/trip_event.dart';
import '../../normalization/models/vehicle_operational_state.dart';
import '../../normalization/models/route_adherence.dart';
import 'situation_detector.dart';

/// Detects if a vehicle has deviated significantly from its assigned route.
///
/// Rule:
/// - If [RouteAdherence] from the Normalization Layer is [RouteAdherence.offRoute],
///   we flag it as a risk.
/// - Minor deviations are tracked but don't generate severe warnings yet.
class OffRouteDetector extends SituationDetector {
  const OffRouteDetector()
    : super(id: 'off_route', name: 'Detector de Desvio de Rota');

  @override
  bool canDetect(OperationalTrip trip) {
    return trip.isActive;
  }

  @override
  OperationalWarning? evaluate(
    OperationalTrip trip,
    VehicleOperationalState? state,
    List<TripEvent> history,
  ) {
    if (state == null) return null;

    if (state.routeAdherence == RouteAdherence.offRoute) {
      return OperationalWarning(
        id: 'warn_off_route_${trip.id}',
        type: 'off_route',
        message: 'Desvio de Rota Detectado',
        severityScore: 30, // Moderate severity
        detectedAt: DateTime.now().toUtc(),
        metadata: {'distance_to_route': state.distanceToRoute},
      );
    }

    return null;
  }
}
