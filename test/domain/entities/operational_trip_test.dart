import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/domain/entities/operational_trip.dart';
import 'package:busflow/domain/enums/trip_status.dart';

void main() {
  group('OperationalTrip Domain Rules', () {
    test(
      'requiresAttention returns false for normal states with low severity',
      () {
        final trip = const OperationalTrip(
          id: '1',
          routeId: 'r1',
          vehicleId: 'v1',
          status: TripStatus.enRoute, // Not requiring attention by itself
          severityScore: 10, // Low severity
        );

        expect(trip.requiresAttention, isFalse);
      },
    );

    test(
      'requiresAttention returns true for status that requires attention',
      () {
        final trip = const OperationalTrip(
          id: '2',
          routeId: 'r1',
          vehicleId: 'v1',
          status: TripStatus
              .interrupted, // requiresAttention is true for this status
          severityScore: 0,
        );

        expect(trip.requiresAttention, isTrue);
      },
    );

    test(
      'requiresAttention returns true when severityScore is high (>= 30)',
      () {
        final trip = const OperationalTrip(
          id: '3',
          routeId: 'r1',
          vehicleId: 'v1',
          status: TripStatus.enRoute, // Status is normal
          severityScore: 30, // Score triggers attention
        );

        expect(trip.requiresAttention, isTrue);
      },
    );

    test('isTerminal correctly identifies terminal states', () {
      final activeTrip = const OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
      );
      final completedTrip = const OperationalTrip(
        id: '2',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.completed,
      );
      final cancelledTrip = const OperationalTrip(
        id: '3',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.cancelled,
      );

      expect(activeTrip.isTerminal, isFalse);
      expect(completedTrip.isTerminal, isTrue);
      expect(cancelledTrip.isTerminal, isTrue);
    });

    test('copyWith properly copies and replaces intelligence properties', () {
      final original = const OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.scheduled,
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
