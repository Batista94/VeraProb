import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/entities/trip_event.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

export '../domain/entities/operational_trip.dart';
export '../domain/entities/trip_event.dart';
export '../domain/enums/event_type.dart';
export '../domain/enums/trip_status.dart';

/// Abstract service for operational control actions.
///
/// This is the core abstraction that decouples the UI from the data source.
abstract class OperationalControlService {
  /// Change the status of a trip and generate an audit event.
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

  /// Update sensitive contract data (Admin Only).
  Future<void> updateContract(String contractId, int newValueCents);

  /// Get all events for a specific trip, newest first.
  List<TripEvent> getEventsForTrip(String tripId);

  /// Get the current operational trip by ID.
  OperationalTrip? getTripById(String tripId);
}
