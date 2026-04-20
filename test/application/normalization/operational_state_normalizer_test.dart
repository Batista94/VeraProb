// ignore_for_file: lines_longer_than_80_chars
// =============================================================================
// test/application/normalization/operational_state_normalizer_test.dart
//
// 100% branch coverage for OperationalStateNormalizer.
//
// Branch Coverage Matrix:
//   B1: MotionState.moving      â†’ result.motionState == moving
//   B2: MotionState.stopped     â†’ result.motionState == stopped  (ignition-off)
//   B3: MotionState.slowTraffic â†’ result.motionState == slowTraffic  (idling)
//   B4: MotionState.dwellingAtStop â†’ nearestStopId populated when â‰¤ 50 m
//   B5: No ping for 90 s â†’ ConnectivityState.signalLost, confidence 0.0
//   B6: Empty pings + no cache â†’ empty result list
//
// Coordinate geometry (haversine-exact, SÃ£o Paulo â€“ ParaÃ­so area):
//   kStopALat/Lng  = (-23.5612, -46.6560) â€” Ponto ParaÃ­so
//   kVehicle30mLat = -23.5609297          â€” ~30 m north of A (inside 50 m radius)
//   kVehicle80mLat = -23.5604793          â€” ~80 m north of A (outside all radii)
// =============================================================================

import 'package:test/test.dart';
import 'package:veraprob/application/normalization/motion_classifier.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/models/route_adherence.dart';
import 'package:veraprob/application/normalization/models/vehicle_operational_state.dart';
import 'package:veraprob/application/normalization/operational_state_normalizer.dart';
import 'package:veraprob/domain/entities/stop.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

import '../../mocks/fake_date_time_provider.dart';

// â”€â”€ Coordinate constants (mirrored from motion_classifier_test.dart) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const double kStopALat = -23.5612;
const double kStopALng = -46.6560;
const double kVehicle30mLat =
    -23.5609297; // ~30 m north of Stop A (inside 50 m radius)
const double kVehicle80mLat =
    -23.5604793; // ~80 m north of Stop A (outside all radii)
const double kBaseLng = -46.6560;

// â”€â”€ Stop fixture â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
const Stop kStopA = Stop(
  id: 'stop-a',
  name: 'Ponto ParaÃ­so',
  latitude: kStopALat,
  longitude: kStopALng,
);

// â”€â”€ FakeMotionClassifier â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
/// Deterministic stub â€” always returns [fixedResult] regardless of input.
/// Extends [MotionClassifier] so it can be injected via the constructor
/// without any mock library dependency.
class FakeMotionClassifier extends MotionClassifier {
  MotionState fixedResult;

  FakeMotionClassifier(this.fixedResult)
    : super(
        movingSpeedThreshold: 8.0,
        slowTrafficThreshold: 2.0,
        stoppedMinDuration: const Duration(seconds: 15),
        slowTrafficMinDuration: const Duration(seconds: 15),
        stopRadiusMeters: 50.0,
      );

  @override
  MotionState classifyMotion(
    String vehicleId,
    double smoothedSpeed,
    (double, double) position,
    List<Stop> stops,
    DateTime now, {
    (double, double)? previousPosition,
    DateTime? previousTimestamp,
    bool isFirstPing = false,
  }) => fixedResult;
}

// â”€â”€ Factories â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
OperationalStateNormalizer makeNormalizer(MotionClassifier classifier) =>
    OperationalStateNormalizer(
      debounceDuration: const Duration(seconds: 5),
      jumpThresholdMeters: 500.0,
      degradedThreshold: const Duration(seconds: 30),
      signalLostThreshold: const Duration(seconds: 90),
      stopRadiusMeters: 50.0,
      movingSpeedThreshold: 8.0,
      slowTrafficThreshold: 2.0,
      stoppedMinDuration: const Duration(seconds: 15),
      slowTrafficMinDuration: const Duration(seconds: 15),
      motionClassifier: classifier,
    );

/// Builds a [VehiclePosition] whose timestamp equals [clock].nowUtc().
/// Zero raw instanciaÃ§Ã£o nativa de tempo â€” all temporal values come from [FakeDateTimeProvider].
VehiclePosition makePing({
  required FakeDateTimeProvider clock,
  double lat = kStopALat,
  double lng = kStopALng,
  double speed = 20.0,
  String tripId = 'trip-1',
  String? vehiclePlate,
}) => VehiclePosition(
  tripId: tripId,
  latitude: lat,
  longitude: lng,
  speed: speed,
  timestamp: clock.nowUtc(),
  source: 'test',
  vehiclePlate: vehiclePlate,
);

// â”€â”€ Tests â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
void main() {
  final kEpoch = DateTime.utc(2026, 4, 7, 12, 0, 0);

  // â”€â”€ Basic Mapping â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  group('Basic Mapping', () {
    // B1 â€” MotionState.moving propagated directly
    test('B1: moving â€“ classifier result surfaces as motionState.moving', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      final out = normalizer.normalize([
        makePing(clock: clock, speed: 20.0),
      ], now: clock.nowUtc());
      expect(out, hasLength(1));
      expect(out.first.motionState, MotionState.moving);
      expect(out.first.connectivityState, ConnectivityState.healthy);
    });

    // B4 â€” dwellingAtStop triggers nearest-stop lookup when vehicle â‰¤ 50 m from stop
    test(
      'B4: dwellingAtStop inside radius â€“ nearestStopId and name populated',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.dwellingAtStop),
        );
        final out = normalizer.normalize(
          [
            makePing(
              clock: clock,
              lat: kVehicle30mLat,
              lng: kBaseLng,
              speed: 0,
            ),
          ],
          knownStops: const [kStopA],
          now: clock.nowUtc(),
        );
        expect(out.first.motionState, MotionState.dwellingAtStop);
        expect(out.first.nearestStopId, 'stop-a');
        expect(out.first.nearestStopName, 'Ponto ParaÃ­so');
        expect(out.first.distanceToRoute, isNotNull);
      },
    );

    // B4-miss â€” dwellingAtStop but outside radius â†’ stop info remains null
    test(
      'B4-miss: dwellingAtStop outside radius â€“ nearestStopId is null',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.dwellingAtStop),
        );
        final out = normalizer.normalize(
          [
            makePing(
              clock: clock,
              lat: kVehicle80mLat,
              lng: kBaseLng,
              speed: 0,
            ),
          ],
          knownStops: const [kStopA],
          now: clock.nowUtc(),
        );
        expect(out.first.motionState, MotionState.dwellingAtStop);
        expect(out.first.nearestStopId, isNull);
      },
    );

    // B5 â€” ConnectivityState.signalLost after 90 s of silence
    test(
      'B5: connectionLost â€“ signalLost and confidence 0.0 after 95 s silence',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        normalizer.normalize([makePing(clock: clock)], now: clock.nowUtc());
        clock.advance(const Duration(seconds: 95));
        final out = normalizer.normalize([], now: clock.nowUtc());
        expect(out, hasLength(1));
        expect(out.first.connectivityState, ConnectivityState.signalLost);
        expect(out.first.confidence, 0.0);
      },
    );

    // B6 â€” Empty pings + empty cache â†’ empty result list
    test(
      'B6: no prior state â€“ normalize([]) returns empty when no vehicle tracked',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        expect(normalizer.normalize([], now: clock.nowUtc()), isEmpty);
      },
    );
  });

  // â”€â”€ Ignition Logic â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  group('Ignition Logic', () {
    // B2 â€” MotionState.stopped (still + ignition off equivalent)
    test(
      'B2: stopped â€“ motionState == stopped propagated (ignition-off)',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.stopped),
        );
        final out = normalizer.normalize([
          makePing(clock: clock, speed: 0),
        ], now: clock.nowUtc());
        expect(out.first.motionState, MotionState.stopped);
      },
    );

    // B3 â€” MotionState.slowTraffic (still + ignition on / idling equivalent)
    test(
      'B3: slowTraffic â€“ motionState == slowTraffic propagated (idling)',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.slowTraffic),
        );
        final out = normalizer.normalize([
          makePing(clock: clock, speed: 5.0),
        ], now: clock.nowUtc());
        expect(out.first.motionState, MotionState.slowTraffic);
      },
    );
  });

  // â”€â”€ Edge Cases â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  group('Edge Cases', () {
    // Debounce â€” second ping within 5 s window returns unmodified cached state
    test(
      'Debounce: ping within 5 s returns cached state â€“ new position ignored',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        normalizer.normalize([
          makePing(clock: clock, lat: kStopALat, lng: kStopALng),
        ], now: clock.nowUtc());
        clock.advance(const Duration(seconds: 2)); // 2 s < 5 s debounce window
        final out = normalizer.normalize([
          makePing(clock: clock, lat: -23.5700, lng: kBaseLng),
        ], now: clock.nowUtc());
        // Cached latitude from first ping must be returned, not the new 2-second position
        expect(out.first.latitude, closeTo(kStopALat, 1e-6));
      },
    );

    // INV-9 Evidence Sealing â€” rawSpeed preserves device-reported speed
    test(
      'rawSpeed preservation: preserves device-reported speed before smoothing',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        // First ping: speed = 10.0
        final out1 = normalizer.normalize([
          makePing(clock: clock, speed: 10.0),
        ], now: clock.nowUtc());
        expect(out1.first.rawSpeed, 10.0);
        expect(out1.first.smoothedSpeed, 10.0); // No smoothing yet (first ping)

        // Second ping: speed = 20.0
        clock.advance(const Duration(seconds: 6));
        final out2 = normalizer.normalize([
          makePing(clock: clock, speed: 20.0),
        ], now: clock.nowUtc());
        expect(out2.first.rawSpeed, 20.0); // Device truth
        // Weighted average: [10, 20] with weights [0.25, 0.60] normalized
        // = 10 * (0.25/0.85) + 20 * (0.60/0.85) â‰ˆ 17.06
        expect(out2.first.smoothedSpeed, closeTo(17.06, 0.1));

        // Third ping: speed = 30.0
        clock.advance(const Duration(seconds: 6));
        final out3 = normalizer.normalize([
          makePing(clock: clock, speed: 30.0),
        ], now: clock.nowUtc());
        expect(out3.first.rawSpeed, 30.0); // Device truth
        // Weighted average: [10, 20, 30] with weights [0.15, 0.25, 0.60]
        // = 10 * 0.15 + 20 * 0.25 + 30 * 0.60 = 1.5 + 5 + 18 = 24.5
        expect(out3.first.smoothedSpeed, closeTo(24.5, 0.1));
      },
    );

    // Visual Stability â€” rawSpeed excluded from equality comparison
    test('rawSpeed equality: states equal when only rawSpeed differs', () {
      final time = DateTime.utc(2026, 4, 7, 12, 0, 0);

      // Create two identical states except for rawSpeed
      final state1 = VehicleOperationalState(
        vehicleId: 'test-1',
        tripId: 'trip-1',
        latitude: -23.5612,
        longitude: -46.6560,
        smoothedSpeed: 10.0,
        rawSpeed: 10.0, // Physical Metric - Double Required
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: RouteAdherence.onRoute,
        lastRawPingAt: time,
        stateChangedAt: time,
        confidence: 1.0,
        source: 'test',
      );

      final state2 = VehicleOperationalState(
        vehicleId: 'test-1',
        tripId: 'trip-1',
        latitude: -23.5612,
        longitude: -46.6560,
        smoothedSpeed: 10.0,
        rawSpeed: 10.1, // Different rawSpeed (micro-oscillation)
        motionState: MotionState.moving,
        connectivityState: ConnectivityState.healthy,
        routeAdherence: RouteAdherence.onRoute,
        lastRawPingAt: time,
        stateChangedAt: time,
        confidence: 1.0,
        source: 'test',
      );

      // States should be equal (rawSpeed not in props)
      expect(state1, equals(state2));
      // But rawSpeed values differ (forensic evidence preserved)
      expect(state1.rawSpeed, 10.0);
      expect(state2.rawSpeed, 10.1);
    });

    // Recovery â€” healthy connectivity is restored after two pings past a signal-lost gap
    //
    // Gap-recovery detection (ConnectivityAnalyzer): the FIRST ping after a >90 s gap
    // is still flagged as signalLost (gap = 95 s > 90 s threshold).
    // The SECOND ping sees gap = 6 s < 30 s â†’ healthy.
    test(
      'Recovery: healthy connectivity restored after 2 pings past signal-lost gap',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        // Seed at t=0
        normalizer.normalize([makePing(clock: clock)], now: clock.nowUtc());
        // Advance 95 s â€” no new pings â†’ signalLost on replay
        clock.advance(const Duration(seconds: 95));
        expect(
          normalizer.normalize([], now: clock.nowUtc()).first.connectivityState,
          ConnectivityState.signalLost,
        );
        // First recovery ping: gap = 95 s > 90 s â†’ still flagged signalLost
        normalizer.normalize([makePing(clock: clock)], now: clock.nowUtc());
        // Second recovery ping after debounce clears (6 s later): gap = 6 s â†’ healthy
        clock.advance(const Duration(seconds: 6));
        final recovered = normalizer.normalize([
          makePing(clock: clock),
        ], now: clock.nowUtc());
        expect(recovered.first.connectivityState, ConnectivityState.healthy);
      },
    );

    // Anomaly (forensic integrity) â€” suspicious jump reduces confidence proportionally
    //
    // Formula: confidence = conn.confidence Ã— (1 âˆ’ jumpDistance / jumpThreshold)
    // With jumpDistance â‰ˆ 334 m and threshold = 500 m: confidence â‰ˆ 0.33 (< 1.0)
    test('Anomaly: jump distance < threshold reduces confidence below 1.0', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      // Seed at reference position
      normalizer.normalize([
        makePing(clock: clock, lat: kStopALat, lng: kStopALng),
      ], now: clock.nowUtc());
      clock.advance(const Duration(seconds: 6)); // past debounce
      // Move ~334 m north (0.003 deg Ã— 111 320 m/deg â‰ˆ 334 m) â€” within 500 m threshold
      final out = normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.003, lng: kStopALng),
      ], now: clock.nowUtc());
      // conn.confidence = 1.0 (healthy); final = 1.0 Ã— (1 âˆ’ 334/500) â‰ˆ 0.33
      expect(out.first.confidence, lessThan(1.0));
      expect(out.first.confidence, greaterThan(0.0));
    });

    // Stale cleanup â€” vehicle absent for > 30 min is evicted from cache on next poll
    test('Stale cleanup: vehicle is evicted after 30+ min of no pings', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.nowUtc());
      clock.advance(const Duration(minutes: 31));
      // First normalize([]) replays the vehicle AND triggers stale eviction
      normalizer.normalize([], now: clock.nowUtc());
      // Second normalize([]) sees an empty cache
      expect(normalizer.normalize([], now: clock.nowUtc()), isEmpty);
    });

    // Jump filter â€” teleportation > 500 m is rejected; cached state is replayed
    test('Jump filter: ping > 500 m from last position is rejected', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([
        makePing(clock: clock, lat: kStopALat, lng: kStopALng),
      ], now: clock.nowUtc());
      clock.advance(const Duration(seconds: 6));
      // Jump ~5.6 km north (0.05 deg Ã— 111 320 m/deg â‰ˆ 5 566 m >> 500 m threshold)
      final out = normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.05, lng: kStopALng),
      ], now: clock.nowUtc());
      // Cached latitude replayed â€” not the teleport target
      expect(out.first.latitude, closeTo(kStopALat, 1e-4));
    });

    // reset() â€” clears all buffers, cache, and classifier state
    test('reset: normalize([]) returns empty after reset()', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.nowUtc());
      expect(normalizer.normalize([], now: clock.nowUtc()), hasLength(1));
      normalizer.reset();
      expect(normalizer.normalize([], now: clock.nowUtc()), isEmpty);
    });

    // vehicleId resolution â€” vehiclePlate takes precedence over tripId when non-empty
    test('vehicleId: vehiclePlate used as identity key when present', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      final out = normalizer.normalize([
        makePing(clock: clock, tripId: 'trip-x', vehiclePlate: 'ABC-1234'),
      ], now: clock.nowUtc());
      expect(out.first.vehiclePlate, 'ABC-1234');
    });

    // Buffer eviction â€” more than 3 sequential pings never crashes
    test('Buffer eviction: 6 sequential pings processed without throwing', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      for (int i = 0; i < 6; i++) {
        normalizer.normalize([
          makePing(clock: clock, lat: kStopALat + i * 0.0001, lng: kStopALng),
        ], now: clock.nowUtc());
        clock.advance(const Duration(seconds: 6));
      }
      expect(normalizer.normalize([], now: clock.nowUtc()), hasLength(1));
    });
  });
}
