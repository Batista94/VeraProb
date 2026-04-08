import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/intelligence/detectors/stopped_vehicle_detector.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

void main() {
  group('StoppedVehicleDetector Rules', () {
    late StoppedVehicleDetector detector;
    late MockDateTimeProvider mockDateTime;

    setUp(() {
      mockDateTime = MockDateTimeProvider();
      when(() => mockDateTime.now()).thenReturn(DateTime.now().toUtc());
      detector = StoppedVehicleDetector(mockDateTime);
    });

    test('canDetect is true only for active trips', () {
      final activeTrip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        scheduledStart: DateTime.now().toUtc(),
      );
      final completedTrip = OperationalTrip(
        id: '2',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.cancelled,
        scheduledStart: DateTime.now().toUtc(),
      );

      expect(detector.canDetect(activeTrip), isTrue);
      expect(detector.canDetect(completedTrip), isFalse);
    });

    test('evaluate returns severe warning for interrupted trips', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.interrupted, // Triggers stoppage currently
        scheduledStart: DateTime.now().toUtc(),
      );

      final warning = detector.evaluate(trip, null, []);
      expect(warning, isNotNull);
      expect(warning!.type, 'vehicle_stopped');
      expect(warning.severityScore, 50); // Highly severe
    });

    test('evaluate returns null for normally flowing trips', () {
      final trip = OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        scheduledStart: DateTime.now().toUtc(),
      );

      final warning = detector.evaluate(trip, null, []);
      expect(warning, isNull);
    });
  });
}
