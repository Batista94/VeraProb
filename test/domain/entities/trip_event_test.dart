import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/trip_event.dart';
import 'package:veraprob/domain/enums/event_type.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

void main() {
  group('TripEvent Domain Rules', () {
    test('summary describes status change accurately', () {
      final event = TripEvent(
        id: 'ev_1',
        tripId: 't_1',
        eventType: EventType.statusChange,
        createdAt: DateTime.now(),
        fromStatus: TripStatus.scheduled,
        toStatus: TripStatus.enRoute,
      );

      expect(event.summary, 'Programada → Em Trânsito');
    });

    test('summary describes delay deviation accurately', () {
      final event = TripEvent(
        id: 'ev_2',
        tripId: 't_2',
        eventType: EventType.delayDetected,
        createdAt: DateTime.now(),
        metadata: {'delay_seconds': 600},
      );

      expect(event.summary, 'Atraso de 10 min detectado');
    });

    test('summary defaults to event type label when no specifics apply', () {
      final event = TripEvent(
        id: 'ev_3',
        tripId: 't_3',
        eventType: EventType.manualOverride,
        createdAt: DateTime.now(),
      );

      expect(event.summary, 'Alteração manual: N/A');
    });

    test('TripEvent retains immutability properties', () {
      final now = DateTime.now();
      final event = TripEvent(
        id: 'ev_1',
        tripId: 't_1',
        eventType: EventType.manualOverride,
        createdAt: now,
      );

      expect(event.id, 'ev_1');
      expect(event.createdAt, now);
      expect(
        event.props.length,
        6,
      ); // Validating Equatable props list has correct length
    });
  });
}
