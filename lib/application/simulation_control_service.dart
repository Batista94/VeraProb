import '../domain/entities/operational_trip.dart';
import '../domain/entities/trip_event.dart';
import '../domain/enums/event_type.dart';
import '../domain/enums/trip_status.dart';
import '../data/services/fleet_simulation_service.dart';
import 'operational_control_service.dart';

/// Concrete implementation of [OperationalControlService] backed by
/// the in-memory [FleetSimulationService].
///
/// All actions mutate the simulation state and generate audit events.
/// When migrating to Supabase, replace this with [SupabaseControlService].
class SimulationControlService implements OperationalControlService {
  final FleetSimulationService _simulation;

  SimulationControlService(this._simulation);

  @override
  Future<TripEvent> updateTripStatus(
    String tripId,
    TripStatus newStatus, {
    String? reason,
  }) async {
    final oldStatus = _simulation.updateTripStatus(tripId, newStatus);

    final event = _simulation.addEvent(
      tripId: tripId,
      eventType: EventType.statusChange,
      fromStatus: oldStatus,
      toStatus: newStatus,
      metadata: {
        // ignore: use_null_aware_elements
        if (reason != null) 'reason': reason,
        'source': 'operator_manual',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    return event;
  }

  @override
  Future<TripEvent> createTripEvent(
    String tripId,
    EventType eventType, {
    Map<String, dynamic>? metadata,
    String? notes,
  }) async {
    final trip = _simulation.getTripById(tripId);

    final event = _simulation.addEvent(
      tripId: tripId,
      eventType: eventType,
      fromStatus: trip?.status,
      toStatus: trip?.status,
      metadata: {
        ...?metadata,
        // ignore: use_null_aware_elements
        if (notes != null) 'notes': notes,
        'source': 'operator_manual',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    return event;
  }

  @override
  Future<TripEvent> resolveAlert(String tripId) async {
    return updateTripStatus(
      tripId,
      TripStatus.enRoute,
      reason: 'Alerta resolvido pelo operador',
    );
  }

  @override
  List<TripEvent> getEventsForTrip(String tripId) {
    return _simulation.getEventsForTrip(tripId);
  }

  @override
  OperationalTrip? getTripById(String tripId) {
    return _simulation.getTripById(tripId);
  }
}
