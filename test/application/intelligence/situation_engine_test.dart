import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pactaflow/application/intelligence/situation_engine.dart';
import 'package:pactaflow/application/operational_control_service.dart';
import 'package:pactaflow/domain/entities/operational_trip.dart';
import 'package:pactaflow/domain/entities/trip_event.dart';
import 'package:pactaflow/domain/enums/trip_status.dart';

class MockOperationalControlService extends Mock
    implements OperationalControlService {}

void main() {
  group('SituationEngine (The Brain) Rules', () {
    late SituationEngine engine;
    late MockOperationalControlService mockControl;

    setUp(() {
      engine = SituationEngine();
      mockControl = MockOperationalControlService();

      // Ensure getEventsForTrip returns empty list by default
      when(() => mockControl.getEventsForTrip(any())).thenReturn(<TripEvent>[]);
    });

    test('Trip with multiple problems sums severity up to a cap (100)', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status:
            TripStatus.interrupted, // Severity 50 from StoppedVehicleDetector
        delaySeconds: 1500, // 25 min -> Severity 40 from DelayDetector
        scheduledStart: DateTime.now(),
      );

      final enrichedTrips = engine.analyze([trip], {}, mockControl);
      final enriched = enrichedTrips.first;

      expect(enriched.warnings.length, 2);
      expect(
        enriched.warnings.map((w) => w.type).toSet(),
        containsAll(['vehicle_stopped', 'delay_critical']),
      );
      expect(enriched.severityScore, 90); // 50 + 40
    });

    test('Severity is capped at 100 even with extreme anomalies', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.interrupted, // Severity 50
        delaySeconds: 5000,
        scheduledStart: DateTime.now(),
      );

      final enrichedTrips = engine.analyze([trip], {}, mockControl);
      expect(enrichedTrips.first.severityScore, lessThanOrEqualTo(100));
    });

    test('Normal trips have 0 severity and no warnings', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        delaySeconds: 0,
        scheduledStart: DateTime.now(),
      );

      final enrichedTrips = engine.analyze([trip], {}, mockControl);
      final enriched = enrichedTrips.first;

      expect(enriched.warnings, isEmpty);
      expect(enriched.severityScore, 0);
    });

    test('If problem is resolved, severity resets to 0', () {
      final badTrip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        delaySeconds: 1200, // Critical delay
        scheduledStart: DateTime.now(),
      );

      final enrichedBad = engine.analyze([badTrip], {}, mockControl).first;
      expect(enrichedBad.severityScore, 40);

      // Operator acts: new pulse comes in fixed
      final fixedTrip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        delaySeconds: 0, // Delay removed
        scheduledStart: DateTime.now(),
      );

      final enrichedFixed = engine.analyze([fixedTrip], {}, mockControl).first;
      expect(enrichedFixed.severityScore, 0);
      expect(enrichedFixed.warnings, isEmpty);
    });
  });
}
