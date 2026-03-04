import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/domain/entities/operational_trip.dart';
import 'package:busflow/domain/enums/trip_status.dart';

void main() {
  group('OperationalTrip', () {
    test('isActive derives from status correctly', () {
      final tripInTransit = OperationalTrip(
        id: '1',
        routeId: 'r1',
        scheduledStart: DateTime.now(),
        status: TripStatus.enRoute,
      );
      expect(tripInTransit.isActive, isTrue);

      final tripFinished = tripInTransit.copyWith(status: TripStatus.completed);
      expect(tripFinished.isActive, isFalse);
    });

    test('isTerminal derives from status correctly', () {
      final tripCompleted = OperationalTrip(
        id: '1',
        routeId: 'r1',
        scheduledStart: DateTime.now(),
        status: TripStatus.completed,
      );
      expect(tripCompleted.isTerminal, isTrue);

      final tripCanceled = tripCompleted.copyWith(status: TripStatus.cancelled);
      expect(tripCanceled.isTerminal, isTrue);

      final tripPending = tripCompleted.copyWith(status: TripStatus.scheduled);
      expect(tripPending.isTerminal, isFalse);
    });

    test('requiresAttention triggers on severity or status', () {
      final normalTrip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        scheduledStart: DateTime.now(),
        status: TripStatus.enRoute,
        severityScore: 10,
      );
      expect(normalTrip.requiresAttention, isFalse);

      final severeTrip = normalTrip.copyWith(severityScore: 30);
      expect(severeTrip.requiresAttention, isTrue);

      final divertedTrip = normalTrip.copyWith(
        status: TripStatus.delayed,
      ); // Delayed requires attention
      expect(divertedTrip.requiresAttention, isTrue);
    });

    test('isFullyAssigned checks driver and vehicle', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        scheduledStart: DateTime.now(),
      );
      expect(trip.isFullyAssigned, isFalse);

      final assignedTrip = trip.copyWith(driverId: 'd1', vehicleId: 'v1');
      expect(assignedTrip.isFullyAssigned, isTrue);
    });

    test('delayDisplay formats strings correctly', () {
      final onTime = OperationalTrip(
        id: '1',
        routeId: 'r1',
        scheduledStart: DateTime.now(),
        delaySeconds: 0,
      );
      expect(onTime.delayDisplay, 'No horário');

      final minorDelay = onTime.copyWith(delaySeconds: 30);
      expect(minorDelay.delayDisplay, '< 1 min');

      final majorDelay = onTime.copyWith(delaySeconds: 120);
      expect(majorDelay.delayDisplay, '+2 min');
    });

    test('routeDisplay combines short and long names gracefully', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        scheduledStart: DateTime.now(),
      );
      expect(trip.routeDisplay, 'r1');

      final shortOnly = trip.copyWith(routeShortName: '100A');
      expect(shortOnly.routeDisplay, '100A');

      final fullInfo = shortOnly.copyWith(routeLongName: 'Centro - Bairro');
      expect(fullInfo.routeDisplay, '100A — Centro - Bairro');
    });

    test('fromJson & toJson map structural fields correctly', () {
      final json = {
        'id': 'trip-uuid',
        'route_id': 'route-uuid',
        'status': 'en_route',
        'scheduled_start': '2026-03-01T10:00:00.000Z',
        'delay_seconds': 60,
        'completion_pct': 0.5,
        'source_type': 'manual',
        'severity_score': 10,
      };

      final trip = OperationalTrip.fromJson(json);
      expect(trip.id, 'trip-uuid');
      expect(trip.status, TripStatus.enRoute);
      expect(trip.delaySeconds, 60);

      final exported = trip.toJson();
      expect(exported['id'], 'trip-uuid');
      expect(exported['status'], 'en_route');
      expect(exported['delay_seconds'], 60);
    });
  });
}
