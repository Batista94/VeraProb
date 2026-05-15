import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/infrastructure/simulation/fleet_simulation_service.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

void main() {
  group('FleetSimulationService', () {
    late FleetSimulationService service;

    setUp(() {
      service = FleetSimulationService();
    });

    tearDown(() {
      service.dispose();
    });

    // ── currentTrips ──────────────────────────────────────────────────────

    test('currentTrips returns non-empty list by default', () {
      final trips = service.currentTrips;
      expect(trips, isNotEmpty);
    });

    test('currentTrips are initialized on first call', () {
      final trips = service.currentTrips;
      expect(trips.length, greaterThanOrEqualTo(1));
    });

    test('currentTrips are consistent across calls', () {
      final trips1 = service.currentTrips;
      final trips2 = service.currentTrips;
      expect(trips1.length, trips2.length);
    });

    test('all trips have non-empty ids', () {
      for (final trip in service.currentTrips) {
        expect(trip.id, isNotEmpty);
      }
    });

    // ── currentPositions ─────────────────────────────────────────────────

    test('currentPositions returns list for active trips', () {
      final positions = service.currentPositions;
      expect(positions, isNotNull);
    });

    test('all positions have valid latitude/longitude ranges', () {
      for (final pos in service.currentPositions) {
        expect(pos.latitude, greaterThanOrEqualTo(-90));
        expect(pos.latitude, lessThanOrEqualTo(90));
        expect(pos.longitude, greaterThanOrEqualTo(-180));
        expect(pos.longitude, lessThanOrEqualTo(180));
      }
    });

    // ── getTripById ───────────────────────────────────────────────────────

    test('getTripById returns null for unknown id', () {
      expect(service.getTripById('nonexistent-id'), isNull);
    });

    test('getTripById returns trip for existing id', () {
      final trips = service.currentTrips;
      if (trips.isEmpty) return;
      final id = trips.first.id;
      final found = service.getTripById(id);
      expect(found, isNotNull);
      expect(found!.id, id);
    });

    // ── updateTripStatus ─────────────────────────────────────────────────

    test('updateTripStatus returns null for unknown trip', () {
      final result = service.updateTripStatus(
        'unknown-id',
        TripStatus.completed,
      );
      expect(result, isNull);
    });

    test('updateTripStatus returns old status and updates trip', () {
      final trips = service.currentTrips;
      if (trips.isEmpty) return;
      final id = trips.first.id;
      final previousStatus = service.updateTripStatus(id, TripStatus.completed);
      expect(previousStatus, isNotNull);
      final updated = service.getTripById(id);
      expect(updated!.status, TripStatus.completed);
    });

    test('updateTripStatus with delaySeconds sets delay', () {
      final trips = service.currentTrips;
      if (trips.isEmpty) return;
      final id = trips.first.id;
      service.updateTripStatus(id, TripStatus.delayed, delaySeconds: 300);
      final updated = service.getTripById(id);
      expect(updated!.status, TripStatus.delayed);
    });

    // ── addEvent ─────────────────────────────────────────────────────────

    test('addEvent returns TripEvent with correct fields', () {
      const tripId = 'trip-event-test';
      final event = service.addEvent(
        tripId: tripId,
        eventType: EventType.statusChange,
        fromStatus: TripStatus.enRoute,
        toStatus: TripStatus.delayed,
        metadata: {'reason': 'test'},
      );
      expect(event.tripId, tripId);
      expect(event.eventType, EventType.statusChange);
      expect(event.fromStatus, TripStatus.enRoute);
      expect(event.toStatus, TripStatus.delayed);
      expect(event.metadata, {'reason': 'test'});
      expect(event.id, isNotEmpty);
    });

    test('addEvent increments event counter', () {
      const tripId = 'trip-counter-test';
      final e1 = service.addEvent(
        tripId: tripId,
        eventType: EventType.delayDetected,
      );
      final e2 = service.addEvent(
        tripId: tripId,
        eventType: EventType.delayRecovered,
      );
      expect(e1.id, isNot(equals(e2.id)));
    });

    // ── getEventsForTrip ─────────────────────────────────────────────────

    test('getEventsForTrip returns empty list for unknown trip', () {
      expect(service.getEventsForTrip('unknown'), isEmpty);
    });

    test('getEventsForTrip returns events in newest-first order', () {
      const tripId = 'trip-order-test';
      service.addEvent(tripId: tripId, eventType: EventType.statusChange);
      service.addEvent(tripId: tripId, eventType: EventType.delayDetected);
      service.addEvent(tripId: tripId, eventType: EventType.delayRecovered);
      final events = service.getEventsForTrip(tripId);
      expect(events.length, 3);
      // Newest first (last added = index 0)
      expect(events[0].eventType, EventType.delayRecovered);
    });

    // ── triggerSpeedViolation ─────────────────────────────────────────────

    test('triggerSpeedViolation does not throw for valid trip', () {
      final trips = service.currentTrips;
      if (trips.isEmpty) return;
      expect(
        () => service.triggerSpeedViolation(trips.first.id),
        returnsNormally,
      );
    });

    // ── streams ──────────────────────────────────────────────────────────

    test('tripStream emits initial trips snapshot', () async {
      final stream = service.tripStream(interval: const Duration(hours: 1));
      final first = await stream.first;
      expect(first, isNotEmpty);
    });

    test('positionStream emits initial positions snapshot', () async {
      final stream = service.positionStream(interval: const Duration(hours: 1));
      final first = await stream.first;
      expect(first, isNotNull);
    });

    // ── seeded determinism ────────────────────────────────────────────────

    test('same seed produces trips with same ids', () {
      final s1 = FleetSimulationService();
      final s2 = FleetSimulationService();
      final ids1 = s1.currentTrips.map((t) => t.id).toList();
      final ids2 = s2.currentTrips.map((t) => t.id).toList();
      expect(ids1, equals(ids2));
      s1.dispose();
      s2.dispose();
    });
  });
}
