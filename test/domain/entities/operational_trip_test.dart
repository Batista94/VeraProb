import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/domain/entities/operational_trip.dart';
import 'package:busflow/domain/enums/trip_status.dart';

void main() {
  group('OperationalTrip Domain Rules', () {
    test(
      'requiresAttention returns false for normal states with low severity',
      () {
        final trip = OperationalTrip(
          id: '1',
          routeId: 'r1',
          vehicleId: 'v1',
          status: TripStatus.enRoute, // Not requiring attention by itself
          severityScore: 10, // Low severity
          scheduledStart: DateTime.now(),
        );

        expect(trip.requiresAttention, isFalse);
      },
    );

    test(
      'requiresAttention returns true for status that requires attention',
      () {
        final trip = OperationalTrip(
          id: '2',
          routeId: 'r1',
          vehicleId: 'v1',
          status: TripStatus
              .interrupted, // requiresAttention is true for this status
          severityScore: 0,
          scheduledStart: DateTime.now(),
        );

        expect(trip.requiresAttention, isTrue);
      },
    );

    test(
      'requiresAttention returns true when severityScore is high (>= 30)',
      () {
        final trip = OperationalTrip(
          id: '3',
          routeId: 'r1',
          vehicleId: 'v1',
          status: TripStatus.enRoute, // Status is normal
          severityScore: 30, // Score triggers attention
          scheduledStart: DateTime.now(),
        );

        expect(trip.requiresAttention, isTrue);
      },
    );

    test('isTerminal correctly identifies terminal states', () {
      final activeTrip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        scheduledStart: DateTime.now(),
      );
      final completedTrip = OperationalTrip(
        id: '2',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.completed,
        scheduledStart: DateTime.now(),
      );
      final cancelledTrip = OperationalTrip(
        id: '3',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.cancelled,
        scheduledStart: DateTime.now(),
      );

      expect(activeTrip.isTerminal, isFalse);
      expect(completedTrip.isTerminal, isTrue);
      expect(cancelledTrip.isTerminal, isTrue);
    });

    test('copyWith properly copies and replaces intelligence properties', () {
      final original = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.scheduled,
        scheduledStart: DateTime.now(),
      );

      final updated = original.copyWith(
        severityScore: 50,
        status: TripStatus.enRoute,
        delaySeconds: 120,
      );

      expect(updated.id, original.id);
      expect(updated.routeId, original.routeId);
      expect(updated.severityScore, 50);
      expect(updated.status, TripStatus.enRoute);
      expect(updated.delaySeconds, 120);
      expect(updated.requiresAttention, isTrue); // 50 > 29
    });
  });
}
