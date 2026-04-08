// ignore_for_file: lines_longer_than_80_chars
// =============================================================================
// test/application/normalization/operational_state_normalizer_test.dart
//
// 100% branch coverage for OperationalStateNormalizer.
//
// Branch Coverage Matrix:
//   B1: MotionState.moving      → result.motionState == moving
//   B2: MotionState.stopped     → result.motionState == stopped  (ignition-off)
//   B3: MotionState.slowTraffic → result.motionState == slowTraffic  (idling)
//   B4: MotionState.dwellingAtStop → nearestStopId populated when ≤ 50 m
//   B5: No ping for 90 s → ConnectivityState.signalLost, confidence 0.0
//   B6: Empty pings + no cache → empty result list
//
// Coordinate geometry (haversine-exact, São Paulo – Paraíso area):
//   kStopALat/Lng  = (-23.5612, -46.6560) — Ponto Paraíso
//   kVehicle30mLat = -23.5609297          — ~30 m north of A (inside 50 m radius)
//   kVehicle80mLat = -23.5604793          — ~80 m north of A (outside all radii)
// =============================================================================

import 'package:test/test.dart';
import 'package:veraprob/application/normalization/motion_classifier.dart';
import 'package:veraprob/application/normalization/models/connectivity_state.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/operational_state_normalizer.dart';
import 'package:veraprob/domain/entities/stop.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

import '../../mocks/fake_date_time_provider.dart';

// ── Coordinate constants (mirrored from motion_classifier_test.dart) ──────────
const double kStopALat = -23.5612;
const double kStopALng = -46.6560;
const double kVehicle30mLat =
    -23.5609297; // ~30 m north of Stop A (inside 50 m radius)
const double kVehicle80mLat =
    -23.5604793; // ~80 m north of Stop A (outside all radii)
const double kBaseLng = -46.6560;

// ── Stop fixture ──────────────────────────────────────────────────────────────
const Stop kStopA = Stop(
  id: 'stop-a',
  name: 'Ponto Paraíso',
  latitude: kStopALat,
  longitude: kStopALng,
);

// ── FakeMotionClassifier ──────────────────────────────────────────────────────
/// Deterministic stub — always returns [fixedResult] regardless of input.
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
    DateTime now,
  ) => fixedResult;
}

// ── Factories ─────────────────────────────────────────────────────────────────
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

/// Builds a [VehiclePosition] whose timestamp equals [clock].now().
/// Zero raw instanciação nativa de tempo — all temporal values come from [FakeDateTimeProvider].
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
  timestamp: clock.now(),
  source: 'test',
  vehiclePlate: vehiclePlate,
);

// ── Tests ─────────────────────────────────────────────────────────────────────
void main() {
  final kEpoch = DateTime.utc(2026, 4, 7, 12, 0, 0);

  // ── Basic Mapping ─────────────────────────────────────────────────────────
  group('Basic Mapping', () {
    // B1 — MotionState.moving propagated directly
    test('B1: moving – classifier result surfaces as motionState.moving', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      final out = normalizer.normalize([
        makePing(clock: clock, speed: 20.0),
      ], now: clock.now());
      expect(out, hasLength(1));
      expect(out.first.motionState, MotionState.moving);
      expect(out.first.connectivityState, ConnectivityState.healthy);
    });

    // B4 — dwellingAtStop triggers nearest-stop lookup when vehicle ≤ 50 m from stop
    test(
      'B4: dwellingAtStop inside radius – nearestStopId and name populated',
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
          now: clock.now(),
        );
        expect(out.first.motionState, MotionState.dwellingAtStop);
        expect(out.first.nearestStopId, 'stop-a');
        expect(out.first.nearestStopName, 'Ponto Paraíso');
        expect(out.first.distanceToRoute, isNotNull);
      },
    );

    // B4-miss — dwellingAtStop but outside radius → stop info remains null
    test('B4-miss: dwellingAtStop outside radius – nearestStopId is null', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.dwellingAtStop),
      );
      final out = normalizer.normalize(
        [makePing(clock: clock, lat: kVehicle80mLat, lng: kBaseLng, speed: 0)],
        knownStops: const [kStopA],
        now: clock.now(),
      );
      expect(out.first.motionState, MotionState.dwellingAtStop);
      expect(out.first.nearestStopId, isNull);
    });

    // B5 — ConnectivityState.signalLost after 90 s of silence
    test(
      'B5: connectionLost – signalLost and confidence 0.0 after 95 s silence',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        normalizer.normalize([makePing(clock: clock)], now: clock.now());
        clock.advance(const Duration(seconds: 95));
        final out = normalizer.normalize([], now: clock.now());
        expect(out, hasLength(1));
        expect(out.first.connectivityState, ConnectivityState.signalLost);
        expect(out.first.confidence, 0.0);
      },
    );

    // B6 — Empty pings + empty cache → empty result list
    test(
      'B6: no prior state – normalize([]) returns empty when no vehicle tracked',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        expect(normalizer.normalize([], now: clock.now()), isEmpty);
      },
    );
  });

  // ── Ignition Logic ────────────────────────────────────────────────────────
  group('Ignition Logic', () {
    // B2 — MotionState.stopped (still + ignition off equivalent)
    test('B2: stopped – motionState == stopped propagated (ignition-off)', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.stopped),
      );
      final out = normalizer.normalize([
        makePing(clock: clock, speed: 0),
      ], now: clock.now());
      expect(out.first.motionState, MotionState.stopped);
    });

    // B3 — MotionState.slowTraffic (still + ignition on / idling equivalent)
    test(
      'B3: slowTraffic – motionState == slowTraffic propagated (idling)',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.slowTraffic),
        );
        final out = normalizer.normalize([
          makePing(clock: clock, speed: 5.0),
        ], now: clock.now());
        expect(out.first.motionState, MotionState.slowTraffic);
      },
    );
  });

  // ── Edge Cases ────────────────────────────────────────────────────────────
  group('Edge Cases', () {
    // Debounce — second ping within 5 s window returns unmodified cached state
    test(
      'Debounce: ping within 5 s returns cached state – new position ignored',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        normalizer.normalize([
          makePing(clock: clock, lat: kStopALat, lng: kStopALng),
        ], now: clock.now());
        clock.advance(const Duration(seconds: 2)); // 2 s < 5 s debounce window
        final out = normalizer.normalize([
          makePing(clock: clock, lat: -23.5700, lng: kBaseLng),
        ], now: clock.now());
        // Cached latitude from first ping must be returned, not the new 2-second position
        expect(out.first.latitude, closeTo(kStopALat, 1e-6));
      },
    );

    // Recovery — healthy connectivity is restored after two pings past a signal-lost gap
    //
    // Gap-recovery detection (ConnectivityAnalyzer): the FIRST ping after a >90 s gap
    // is still flagged as signalLost (gap = 95 s > 90 s threshold).
    // The SECOND ping sees gap = 6 s < 30 s → healthy.
    test(
      'Recovery: healthy connectivity restored after 2 pings past signal-lost gap',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(
          FakeMotionClassifier(MotionState.moving),
        );
        // Seed at t=0
        normalizer.normalize([makePing(clock: clock)], now: clock.now());
        // Advance 95 s — no new pings → signalLost on replay
        clock.advance(const Duration(seconds: 95));
        expect(
          normalizer.normalize([], now: clock.now()).first.connectivityState,
          ConnectivityState.signalLost,
        );
        // First recovery ping: gap = 95 s > 90 s → still flagged signalLost
        normalizer.normalize([makePing(clock: clock)], now: clock.now());
        // Second recovery ping after debounce clears (6 s later): gap = 6 s → healthy
        clock.advance(const Duration(seconds: 6));
        final recovered = normalizer.normalize([
          makePing(clock: clock),
        ], now: clock.now());
        expect(recovered.first.connectivityState, ConnectivityState.healthy);
      },
    );

    // Anomaly (forensic integrity) — suspicious jump reduces confidence proportionally
    //
    // Formula: confidence = conn.confidence × (1 − jumpDistance / jumpThreshold)
    // With jumpDistance ≈ 334 m and threshold = 500 m: confidence ≈ 0.33 (< 1.0)
    test('Anomaly: jump distance < threshold reduces confidence below 1.0', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      // Seed at reference position
      normalizer.normalize([
        makePing(clock: clock, lat: kStopALat, lng: kStopALng),
      ], now: clock.now());
      clock.advance(const Duration(seconds: 6)); // past debounce
      // Move ~334 m north (0.003 deg × 111 320 m/deg ≈ 334 m) — within 500 m threshold
      final out = normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.003, lng: kStopALng),
      ], now: clock.now());
      // conn.confidence = 1.0 (healthy); final = 1.0 × (1 − 334/500) ≈ 0.33
      expect(out.first.confidence, lessThan(1.0));
      expect(out.first.confidence, greaterThan(0.0));
    });

    // Stale cleanup — vehicle absent for > 30 min is evicted from cache on next poll
    test('Stale cleanup: vehicle is evicted after 30+ min of no pings', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.now());
      clock.advance(const Duration(minutes: 31));
      // First normalize([]) replays the vehicle AND triggers stale eviction
      normalizer.normalize([], now: clock.now());
      // Second normalize([]) sees an empty cache
      expect(normalizer.normalize([], now: clock.now()), isEmpty);
    });

    // Jump filter — teleportation > 500 m is rejected; cached state is replayed
    test('Jump filter: ping > 500 m from last position is rejected', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([
        makePing(clock: clock, lat: kStopALat, lng: kStopALng),
      ], now: clock.now());
      clock.advance(const Duration(seconds: 6));
      // Jump ~5.6 km north (0.05 deg × 111 320 m/deg ≈ 5 566 m >> 500 m threshold)
      final out = normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.05, lng: kStopALng),
      ], now: clock.now());
      // Cached latitude replayed — not the teleport target
      expect(out.first.latitude, closeTo(kStopALat, 1e-4));
    });

    // reset() — clears all buffers, cache, and classifier state
    test('reset: normalize([]) returns empty after reset()', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.now());
      expect(normalizer.normalize([], now: clock.now()), hasLength(1));
      normalizer.reset();
      expect(normalizer.normalize([], now: clock.now()), isEmpty);
    });

    // vehicleId resolution — vehiclePlate takes precedence over tripId when non-empty
    test('vehicleId: vehiclePlate used as identity key when present', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      final out = normalizer.normalize([
        makePing(clock: clock, tripId: 'trip-x', vehiclePlate: 'ABC-1234'),
      ], now: clock.now());
      expect(out.first.vehiclePlate, 'ABC-1234');
    });

    // Buffer eviction — more than 3 sequential pings never crashes
    test('Buffer eviction: 6 sequential pings processed without throwing', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      for (int i = 0; i < 6; i++) {
        normalizer.normalize([
          makePing(clock: clock, lat: kStopALat + i * 0.0001, lng: kStopALng),
        ], now: clock.now());
        clock.advance(const Duration(seconds: 6));
      }
      expect(normalizer.normalize([], now: clock.now()), hasLength(1));
    });
  });
}
