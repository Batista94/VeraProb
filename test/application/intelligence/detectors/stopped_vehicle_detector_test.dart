import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/intelligence/detectors/stopped_vehicle_detector.dart';
import 'package:busflow/domain/entities/operational_trip.dart';
import 'package:busflow/domain/enums/trip_status.dart';

void main() {
  group('StoppedVehicleDetector Rules', () {
    late StoppedVehicleDetector detector;

    setUp(() {
      detector = const StoppedVehicleDetector();
    });

    test('canDetect is true only for active trips', () {
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
        status: TripStatus.cancelled,
      );

      expect(detector.canDetect(activeTrip), isTrue);
      expect(detector.canDetect(completedTrip), isFalse);
    });

    test('evaluate returns severe warning for interrupted trips', () {
      final trip = const OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.interrupted, // Triggers stoppage currently
      );

      final warning = detector.evaluate(trip, []);
      expect(warning, isNotNull);
      expect(warning!.type, 'vehicle_stopped');
      expect(warning.severityScore, 50); // Highly severe
    });

    test('evaluate returns null for normally flowing trips', () {
      final trip = const OperationalTrip(
        id: '1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
      );

      final warning = detector.evaluate(trip, []);
      expect(warning, isNull);
    });
  });
}
