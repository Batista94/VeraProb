import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/normalization/operational_state_normalizer.dart';
import 'package:busflow/domain/entities/vehicle_position.dart';
import 'package:busflow/domain/entities/stop.dart';
import 'package:busflow/domain/enums/motion_state.dart';
import 'package:busflow/domain/enums/connectivity_state.dart';

void main() {
  late OperationalStateNormalizer normalizer;
  late DateTime now;
  const String vehicle1 = 'trip-100';

  setUp(() {
    normalizer = OperationalStateNormalizer(
      debounceDuration: const Duration(seconds: 5),
      jumpThresholdMeters: 500,
      degradedThreshold: const Duration(seconds: 30),
      signalLostThreshold: const Duration(seconds: 90),
      stopRadiusMeters: 50,
      movingSpeedThreshold: 8.0,
      slowTrafficThreshold: 2.0,
      stoppedMinDuration: const Duration(seconds: 15),
      slowTrafficMinDuration: const Duration(seconds: 15),
    );
    now = DateTime(2025, 1, 1, 12, 0, 0);
  });

  VehiclePosition createPing(
    double lat,
    double lng, {
    double speed = 20.0,
    Duration offset = Duration.zero,
  }) {
    return VehiclePosition(
      tripId: vehicle1,
      latitude: lat,
      longitude: lng,
      speed: speed,
      timestamp: now.add(offset),
      source: 'test',
    );
  }

  test('debounces frequent updates within threshold', () {
    final pings = [createPing(-23.5, -46.6)];

    // First ping emits normally
    final out1 = normalizer.normalize(pings, now: now);
    expect(out1.length, 1);
    expect(out1.first.latitude, -23.5);

    // Second ping happens 2 seconds later (under 5s threshold)
    final fastPing = [
      createPing(-23.51, -46.61, offset: const Duration(seconds: 2)),
    ];
    final out2 = normalizer.normalize(
      fastPing,
      now: now.add(const Duration(seconds: 2)),
    );

    // Should return cached state, not process new ping
    expect(out2.length, 1);
    expect(out2.first.latitude, -23.5); // Still the old latitude!
  });

  test('filters impossible jumps (teleportation)', () {
    // Ping 1
    normalizer.normalize([createPing(-23.5000, -46.6000)], now: now);

    // Ping 2 happens 3 seconds later, but distance is > 5km
    now = now.add(const Duration(seconds: 3));
    final jumpPing = [
      createPing(-23.5500, -46.6500, offset: const Duration(seconds: 3)),
    ]; // Far away

    final out = normalizer.normalize(jumpPing, now: now);

    // Jump ping ignored, old latitude returned
    expect(out.first.latitude, -23.5000);
  });

  test('applies spatial smoothing to latest positions', () {
    // We send 3 pings spaced 6 seconds apart (so no debounce)
    normalizer.normalize([createPing(10.0, 10.0)], now: now);

    now = now.add(const Duration(seconds: 6));
    normalizer.normalize([createPing(10.0, 20.0)], now: now);

    now = now.add(const Duration(seconds: 6));
    final out = normalizer.normalize([createPing(10.0, 30.0)], now: now);

    // Weights: [0.15, 0.25, 0.60]
    // lat = 10.0
    // lng = (10*0.15) + (20*0.25) + (30*0.60) = 1.5 + 5.0 + 18.0 = 24.5
    expect(out.first.latitude, 10.0);
    expect(out.first.longitude, 24.5);
  });

  test('transitions to dwellingAtStop based on geofence', () {
    final stops = [
      const Stop(
        id: 's1',
        name: 'Metro',
        latitude: -23.5000,
        longitude: -46.6000,
      ),
    ];

    // Vehicle approaches stop (speed 0)
    normalizer.normalize(
      [createPing(-23.5001, -46.6001, speed: 0)],
      knownStops: stops,
      now: now,
    );
    final out1 = normalizer.normalize(
      [],
      knownStops: stops,
      now: now,
    ); // Check cache
    expect(
      out1.first.motionState,
      MotionState.moving,
    ); // Not stopped long enough

    // Wait 16 seconds (passes stoppedMinDuration)
    now = now.add(const Duration(seconds: 16));
    final out2 = normalizer.normalize(
      [createPing(-23.5001, -46.6001, speed: 0)],
      knownStops: stops,
      now: now,
    );

    // Should detect stop
    expect(out2.first.motionState, MotionState.dwellingAtStop);
    expect(out2.first.nearestStopId, 's1');
  });

  test('handles missing vehicles by degrading connectivity state', () {
    // Initial ping
    normalizer.normalize([createPing(0, 0)], now: now);

    // Fast forward 40 seconds (no new ping sent in rawPositions)
    now = now.add(const Duration(seconds: 40));
    final out1 = normalizer.normalize([], now: now); // Empty ping array
    expect(out1.first.connectivityState, ConnectivityState.degraded);
    expect(out1.first.confidence, 0.5);

    // Fast forward to 100 seconds
    now = now.add(const Duration(seconds: 60)); // total 100s
    final out2 = normalizer.normalize([], now: now);
    expect(out2.first.connectivityState, ConnectivityState.signalLost);
    expect(out2.first.confidence, 0.0);
  });
}
