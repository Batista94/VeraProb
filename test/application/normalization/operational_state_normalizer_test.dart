import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/normalization/operational_state_normalizer.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';
import 'package:veraprob/domain/entities/stop.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';

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
    // Use micro-offsets (meters-scale) to avoid jump rejection.
    // 0.001 deg ≈ 111m, so 0.0001 ≈ 11m — well within 500m threshold.
    normalizer.normalize([createPing(-23.5000, -46.6000)], now: now);

    now = now.add(const Duration(seconds: 6));
    normalizer.normalize([createPing(-23.5001, -46.6001)], now: now);

    now = now.add(const Duration(seconds: 6));
    final out = normalizer.normalize([
      createPing(-23.5002, -46.6002),
    ], now: now);

    // Verify smoothing was applied — result should be a weighted average,
    // not simply the last ping's coordinates.
    final result = out.first;
    expect(result.latitude, isNot(-23.5002));
    expect(result.longitude, isNot(-46.6002));
    // Weighted: [0.15, 0.25, 0.60] of the three positions
    expect(result.latitude, closeTo(-23.50014, 1e-5));
    expect(result.longitude, closeTo(-46.60014, 1e-5));
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

  test('reset() clears internal state', () {
    normalizer.normalize([createPing(0, 0)], now: now);
    expect(normalizer.normalize([], now: now).length, 1);

    normalizer.reset();
    expect(normalizer.normalize([], now: now), isEmpty);
  });

  test('transitions to slowTraffic state', () {
    // Phase 1: Moving
    normalizer.normalize([createPing(0, 0, speed: 20)], now: now);

    // Phase 2: Enter slow speed (3.0 kmh, between 2 and 8)
    now = now.add(const Duration(seconds: 10));
    final out1 = normalizer.normalize([createPing(0, 0, speed: 3.0)], now: now);
    expect(out1.first.motionState, MotionState.moving);

    // Phase 3: Wait long enough (16s > 15s slowTrafficMinDuration)
    now = now.add(const Duration(seconds: 16));
    final out2 = normalizer.normalize([createPing(0, 0, speed: 3.0)], now: now);
    expect(out2.first.motionState, MotionState.slowTraffic);
  });

  test('exercises buffer eviction when length > 3', () {
    for (int i = 1; i <= 5; i++) {
      normalizer.normalize([createPing(i.toDouble(), i.toDouble())], now: now);
      now = now.add(const Duration(seconds: 6));
    }
    // No crash, buffer should have been pruned to 3
    final out = normalizer.normalize([createPing(6, 6)], now: now);
    expect(out, isNotEmpty);
  });

  test('exercises line 73 by passing now as null', () {
    // This just ensures the branch for now == null is taken
    final out = normalizer.normalize([createPing(0, 0)], now: null);
    expect(out, isNotEmpty);
  });
}
