import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/application/intelligence/detectors/stopped_vehicle_detector.dart';
import 'package:veraprob/application/normalization/operational_state_normalizer.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/domain/shared/coordinate.dart';

class MockDateTimeProvider extends Mock implements IDateTimeProvider {}

void main() {
  group('StoppedVehicleDetector Accuracy (Fleet Telemetry Data Scientist)', () {
    late StoppedVehicleDetector detector;
    late MockDateTimeProvider mockDateTime;
    late OperationalStateNormalizer normalizer;
    late DateTime now;
    late Random random;

    const double baseLat = -23.5505;
    const double baseLng = -46.6333;
    const Coordinate center = Coordinate(baseLat, baseLng);

    setUp(() {
      mockDateTime = MockDateTimeProvider();
      when(() => mockDateTime.nowUtc()).thenReturn(DateTime.now().toUtc());
      detector = StoppedVehicleDetector(mockDateTime);
      normalizer = OperationalStateNormalizer(
        debounceDuration: Duration.zero,
        stoppedMinDuration: const Duration(seconds: 30),
        movingSpeedThreshold: 5.0,
        slowTrafficThreshold: 4.9,
      );
      now = DateTime.now().toUtc();
      random = Random(42); // Reset random seed for every test
    });

    Coordinate generateNoisyCoordinate(Coordinate base, double radiusMeters) {
      final double theta = random.nextDouble() * 2 * pi;
      final double r = radiusMeters;
      const double latDegreePerMeter = 1.0 / 110574.0;
      const double lngDegreePerMeter = 1.0 / 101650.0;
      return Coordinate(
        base.latitude + (r * sin(theta) * latDegreePerMeter),
        base.longitude + (r * cos(theta) * lngDegreePerMeter),
      );
    }

    VehiclePosition createPing(
      Coordinate coord, {
      double speed = 0.0,
      required Duration offset,
    }) {
      return VehiclePosition(
        tripId: 'trip-100',
        latitude: coord.latitude,
        longitude: coord.longitude,
        speed: speed,
        timestamp: now.add(offset),
        source: 'gps_samba_test',
      );
    }

    test('The Jitter Test (GPS Samba) - Stationary must remain stopped', () {
      var currentNow = now;

      // Phase 1: Establish stop
      for (int i = 0; i <= 40; i += 10) {
        currentNow = now.add(Duration(seconds: i));
        normalizer.normalize([
          createPing(center, offset: Duration(seconds: i)),
        ], now: currentNow);
      }

      // Phase 2: Moderate Jitter (5m)
      for (int i = 1; i <= 5; i++) {
        currentNow = currentNow.add(const Duration(seconds: 10));
        final jitterCoord = generateNoisyCoordinate(center, 5.0);
        final results = normalizer.normalize([
          createPing(
            jitterCoord,
            speed: 0.5,
            offset: currentNow.difference(now),
          ),
        ], now: currentNow);
        expect(results.first.motionState, MotionState.stopped);
        expect(results.first.confidence, greaterThanOrEqualTo(0.6));
      }

      // Phase 3: Excessive noise (300m jump)
      currentNow = currentNow.add(const Duration(seconds: 10));
      final excessiveJitter = generateNoisyCoordinate(center, 300.0);
      final noisyResults = normalizer.normalize([
        createPing(
          excessiveJitter,
          speed: 1.0,
          offset: currentNow.difference(now),
        ),
      ], now: currentNow);

      expect(noisyResults.first.confidence, lessThan(0.5));
    });

    test('Signal Gap Recovery - 10-minute gap forensics', () {
      var currentNow = now;
      normalizer.normalize([
        createPing(center, offset: Duration.zero),
      ], now: currentNow);
      currentNow = currentNow.add(const Duration(minutes: 10));

      // Call with empty pings to trigger degraded/replay state
      final replayResults = normalizer.normalize([], now: currentNow);
      expect(replayResults.first.motionState, MotionState.stopped);
      expect(replayResults.first.connectivityState.name, 'signalLost');

      final trip = OperationalTrip(
        id: 'trip-100',
        routeId: 'r1',
        vehicleId: 'v1',
        status: TripStatus.enRoute,
        scheduledStart: now,
      );

      final warning = detector.evaluate(trip, replayResults.first, []);
      expect(warning, isNotNull);
      expect(warning!.message, contains('VeÃ­culo Parado na Via: 10 min'));
    });

    test('Dwell Time Transition - Moving to Stopped state transition', () {
      var currentNow = now;
      normalizer.normalize([
        createPing(center, speed: 20.0, offset: Duration.zero),
      ], now: currentNow);

      currentNow = now.add(const Duration(seconds: 10));
      normalizer.normalize([
        createPing(center, speed: 0.0, offset: const Duration(seconds: 10)),
      ], now: currentNow);
      currentNow = now.add(const Duration(seconds: 20));
      normalizer.normalize([
        createPing(center, speed: 0.0, offset: const Duration(seconds: 20)),
      ], now: currentNow);

      currentNow = now.add(const Duration(seconds: 49)); // 29s since t=20
      final resWait1 = normalizer.normalize([
        createPing(center, speed: 0.0, offset: const Duration(seconds: 49)),
      ], now: currentNow);
      expect(resWait1.first.motionState, MotionState.moving);

      currentNow = now.add(const Duration(seconds: 51)); // 31s since t=20
      final resWait2 = normalizer.normalize([
        createPing(center, speed: 0.0, offset: const Duration(seconds: 51)),
      ], now: currentNow);
      expect(resWait2.first.motionState, MotionState.stopped);
    });

    test('Trip Transition Forensics - Continuity across trips', () {
      var currentNow = now;
      const String plate = 'BRA-2024';

      // 1. First trip ping
      normalizer.normalize([
        VehiclePosition(
          tripId: 'trip-1',
          vehiclePlate: plate,
          latitude: baseLat,
          longitude: baseLng,
          timestamp: currentNow,
          source: 'test',
        ),
      ], now: currentNow);

      // 2. 10-minute gap
      currentNow = currentNow.add(const Duration(minutes: 10));

      // 3. Second trip ping (different tripId, same plate)
      final results = normalizer.normalize([
        VehiclePosition(
          tripId: 'trip-2',
          vehiclePlate: plate,
          latitude: baseLat,
          longitude: baseLng,
          timestamp: currentNow,
          source: 'test',
        ),
      ], now: currentNow);

      expect(results.first.tripId, 'trip-2');
      expect(results.first.vehicleId, plate);
      expect(results.first.connectivityState.name, 'signalLost');
    });
  });
}
