import 'package:pactaflow/application/operational_control_service.dart';
import 'package:pactaflow/domain/entities/trip_event.dart';
import 'package:pactaflow/domain/enums/event_type.dart';
import 'package:pactaflow/domain/enums/trip_status.dart';
import 'package:pactaflow/domain/entities/operational_trip.dart';

/// A pure Spy Service that intercepts Mutator calls.
///
/// It extends [OperationalControlService] but skips any real Supabase logic,
/// just incrementing [callCount] to prove whether the Interceptor blocked or allowed the action.
class MockMutatorService implements OperationalControlService {
  int callCount = 0;
  bool shouldThrowError = false;

  TripEvent _dummyEvent(String tripId) => TripEvent(
    id: 'mock-event',
    tripId: tripId,
    eventType: EventType.manualOverride,
    createdAt: DateTime.now(),
  );

  @override
  Future<TripEvent> resolveAlert(String tripId) async {
    callCount++;
    if (shouldThrowError) {
      throw Exception('Mock Runtime Crash during Mutation');
    }
    return _dummyEvent(tripId);
  }

  @override
  Future<TripEvent> createTripEvent(
    String tripId,
    EventType eventType, {
    Map<String, dynamic>? metadata,
    String? notes,
  }) async {
    callCount++;
    if (shouldThrowError) throw Exception('Crash');
    return _dummyEvent(tripId);
  }

  @override
  Future<TripEvent> updateTripStatus(
    String tripId,
    TripStatus newStatus, {
    String? reason,
  }) async {
    callCount++;
    if (shouldThrowError) throw Exception('Crash');
    return _dummyEvent(tripId);
  }

  @override
  List<TripEvent> getEventsForTrip(String tripId) => [];

  @override
  OperationalTrip? getTripById(String tripId) => null;
}
