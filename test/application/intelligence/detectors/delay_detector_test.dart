import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/intelligence/detectors/delay_detector.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

void main() {
  group('DelayDetector Rules', () {
    late DelayDetector detector;

    setUp(() {
      detector = const DelayDetector();
    });

    test('canDetect is true for active or scheduled trips', () {
      final activeTrip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        scheduledStart: DateTime.now(),
      );
      final scheduledTrip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.scheduled,
        scheduledStart: DateTime.now(),
      );
      final completedTrip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.completed,
        scheduledStart: DateTime.now(),
      );

      expect(detector.canDetect(activeTrip), isTrue);
      expect(detector.canDetect(scheduledTrip), isTrue);
      expect(detector.canDetect(completedTrip), isFalse);
    });

    test('evaluate returns null for delay < 3 minutes', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        delaySeconds: 120, // 2 minutes
        scheduledStart: DateTime.now(),
      );

      final warning = detector.evaluate(trip, null, []);
      expect(warning, isNull);
    });

    test('evaluate returns risk warning for delay between 3 and 9 minutes', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        delaySeconds: 300, // 5 minutes
        scheduledStart: DateTime.now(),
      );

      final warning = detector.evaluate(trip, null, []);
      expect(warning, isNotNull);
      expect(warning!.type, 'delay_risk');
      expect(warning.severityScore, 20);
      expect(warning.metadata!['delay_minutes'], 5);
    });

    test('evaluate returns critical warning for delay >= 10 minutes', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        delaySeconds: 720, // 12 minutes
        scheduledStart: DateTime.now(),
      );

      final warning = detector.evaluate(trip, null, []);
      expect(warning, isNotNull);
      expect(warning!.type, 'delay_critical');
      expect(warning.severityScore, 40);
      expect(warning.metadata!['delay_minutes'], 12);
    });
  });
}
