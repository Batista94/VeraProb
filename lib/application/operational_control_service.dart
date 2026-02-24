import '../domain/entities/operational_trip.dart';
import '../domain/entities/trip_event.dart';
import '../domain/enums/event_type.dart';
import '../domain/enums/trip_status.dart';

/// Abstract service for operational control actions.
///
/// This is the core abstraction that decouples the UI from the data source.
/// Today: connected to [FleetSimulationService].
/// Future: swap for [SupabaseControlService] without touching UI.
abstract class OperationalControlService {
  /// Change the status of a trip and generate an audit event.
  ///
  /// Returns the generated [TripEvent] if successful.
  Future<TripEvent> updateTripStatus(
    String tripId,
    TripStatus newStatus, {
    String? reason,
  });

  /// Create a manual operational event (occurrence) for a trip.
  Future<TripEvent> createTripEvent(
    String tripId,
    EventType eventType, {
    Map<String, dynamic>? metadata,
    String? notes,
  });

  /// Mark an alert as resolved: sets trip back to [enRoute] with delay = 0.
  Future<TripEvent> resolveAlert(String tripId);

  /// Get all events for a specific trip, newest first.
  List<TripEvent> getEventsForTrip(String tripId);

  /// Get the current operational trip by ID.
  OperationalTrip? getTripById(String tripId);
}
