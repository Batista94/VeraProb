import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/intelligence/detectors/signal_loss_detector.dart';
import 'package:veraprob/domain/entities/operational_trip.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';
import 'package:veraprob/domain/enums/trip_status.dart';
import 'package:veraprob/testing/fakes/fake_date_time_provider.dart';

void main() {
  final now = DateTime.utc(2026, 4, 7, 20, 0, 0);
  final twoMinutesAgo = now.subtract(const Duration(minutes: 2));

  VehicleOperationalState makeState(
    ConnectivityState connectivityState, {
    DateTime? lastPingAt,
  }) => VehicleOperationalState(
    rawSpeed: 0.0,
    vehicleId: 'v1',
    tripId: 'trip-1',
    latitude: -23.5,
    longitude: -46.6,
    smoothedSpeed: 0.0,
    motionState: MotionState.stopped,
    connectivityState: connectivityState,
    routeAdherence: RouteAdherence.onRoute,
    lastRawPingAt: lastPingAt ?? twoMinutesAgo,
    stateChangedAt: lastPingAt ?? twoMinutesAgo,
    confidence: connectivityState == ConnectivityState.signalLost ? 0.0 : 1.0,
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
  group('SignalLossDetector', () {
    late SignalLossDetector detector;
    late FakeDateTimeProvider fakeTimeProvider;
    setUp(() {
      fakeTimeProvider = FakeDateTimeProvider(now);
      detector = SignalLossDetector(fakeTimeProvider);
    });

    test('canDetect is true for active trips', () {
      expect(detector.canDetect(makeTrip()), isTrue);
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

    test('evaluate returns warning when signal is lost', () {
      final warning = detector.evaluate(
        makeTrip(),
        makeState(ConnectivityState.signalLost),
        [],
      );
      expect(warning, isNotNull);
      expect(warning!.type, 'signal_lost');
      expect(warning.severityScore, 40);
      expect(warning.message, contains('Perda de Sinal GPS'));
    });

    test('warning metadata includes last_ping_at and seconds_offline', () {
      final warning = detector.evaluate(
        makeTrip(),
        makeState(ConnectivityState.signalLost),
        [],
      );
      expect(warning!.metadata, containsPair('last_ping_at', isA<String>()));
      expect(warning.metadata, containsPair('seconds_offline', isA<int>()));
    });

    test('evaluate returns null when signal is healthy', () {
      final warning = detector.evaluate(
        makeTrip(),
        makeState(ConnectivityState.healthy),
        [],
      );
      expect(warning, isNull);
    });

    test('evaluate returns null when signal is degraded', () {
      final warning = detector.evaluate(
        makeTrip(),
        makeState(ConnectivityState.degraded),
        [],
      );
      expect(warning, isNull);
    });
  });
}
