import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';

void main() {
  group('VehicleOperationalState', () {
    test('copyWith updates fields correctly', () {
      final state = VehicleOperationalState(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.0,
        longitude: -46.0,
        smoothedSpeed: 10.0,
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        lastRawPingAt: DateTime.utc(2026, 3, 1),
        stateChangedAt: DateTime.utc(2026, 3, 1),
        confidence: 1.0,
        source: 'gps',
      );

      final newState = state.copyWith(
        latitude: -24.0,
        motionState: MotionState.stopped,
        nearestStopId: 's1',
      );

      expect(newState.latitude, -24.0);
      expect(newState.longitude, -46.0); // Kept original
      expect(newState.motionState, MotionState.stopped);
      expect(newState.nearestStopId, 's1');
    });

    test('requiresAttention returns true for lost signal or off route', () {
      // Base healthy
      final state = VehicleOperationalState(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.0,
        longitude: -46.0,
        smoothedSpeed: 10.0,
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: RouteAdherence.onRoute,
        lastRawPingAt: DateTime.utc(2026, 3, 1),
        stateChangedAt: DateTime.utc(2026, 3, 1),
        confidence: 1.0,
        source: 'gps',
      );

      expect(state.requiresAttention, isFalse);

      final lost = state.copyWith(
        connectivityState: ConnectivityState.signalLost,
      );
      expect(lost.requiresAttention, isTrue);

      final offRoute = state.copyWith(routeAdherence: RouteAdherence.offRoute);
      expect(offRoute.requiresAttention, isTrue);
    });

    test('props returns correct equatable items', () {
      final time = DateTime.utc(2026, 3, 1);
      final state1 = VehicleOperationalState(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.0,
        longitude: -46.0,
        smoothedSpeed: 10.0,
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: RouteAdherence.onRoute,
        lastRawPingAt: time,
        stateChangedAt: time,
        confidence: 1.0,
        source: 'gps',
      );

      final state2 = VehicleOperationalState(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.0,
        longitude: -46.0,
        smoothedSpeed: 10.0,
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: RouteAdherence.onRoute,
        lastRawPingAt: time,
        stateChangedAt: time,
        confidence: 1.0,
        source: 'gps',
      );

      expect(state1, equals(state2));
    });
  });
}
