import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/intelligence/detectors/off_route_detector.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';
import 'package:veraprob/domain/enums/trip_status.dart';

void main() {
  final now = DateTime.now().toUtc();

  VehicleOperationalState makeState(RouteAdherence adherence) =>
      VehicleOperationalState(
        vehicleId: 'v1',
        tripId: 'trip-1',
        latitude: -23.5,
        longitude: -46.6,
        smoothedSpeed: 40.0,
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: adherence,
        lastRawPingAt: now,
        stateChangedAt: now,
        confidence: 1.0,
        source: 'gps',
      );

  OperationalTrip makeTrip({TripStatus status = TripStatus.enRoute}) =>
      OperationalTrip(
        id: 'trip-1',
        routeId: 'r1',
        vehicleId: 'v1',
        status: status,
        scheduledStart: now,
      );

  group('OffRouteDetector', () {
    late OffRouteDetector detector;
    setUp(() => detector = const OffRouteDetector());

    test('canDetect is true for active trips', () {
      expect(detector.canDetect(makeTrip(status: TripStatus.enRoute)), isTrue);
    });

    test('canDetect is false for completed trips', () {
      expect(
        detector.canDetect(makeTrip(status: TripStatus.completed)),
        isFalse,
      );
    });

    test('evaluate returns null when state is null', () {
      expect(detector.evaluate(makeTrip(), null, []), isNull);
    });

    test('evaluate returns warning when offRoute', () {
      final warning = detector.evaluate(
        makeTrip(),
        makeState(RouteAdherence.offRoute),
        [],
      );
      expect(warning, isNotNull);
      expect(warning!.type, 'off_route');
      expect(warning.severityScore, 30);
    });

    test('evaluate returns null when onRoute', () {
      final warning = detector.evaluate(
        makeTrip(),
        makeState(RouteAdherence.onRoute),
        [],
      );
      expect(warning, isNull);
    });

    test('evaluate returns null when minorDeviation', () {
      final warning = detector.evaluate(
        makeTrip(),
        makeState(RouteAdherence.minorDeviation),
        [],
      );
      expect(warning, isNull);
    });
  });
}
