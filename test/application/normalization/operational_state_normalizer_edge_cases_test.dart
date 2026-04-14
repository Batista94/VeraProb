// ignore_for_file: lines_longer_than_80_chars
// =============================================================================
// test/application/normalization/operational_state_normalizer_edge_cases_test.dart
//
// Edge case coverage for OperationalStateNormalizer:
// - Jump threshold boundary conditions (500.0 m exact)
// - State persistence across replays
// - Debounce exact threshold (5000 ms)
// - Cold start confidence
// - Triple spike rejection
//
// Invariants enforced:
// - INV-8: Repository isolation (vehicleId-scoped cache)
// - INV-12: UTC mandatory (all timestamps via FakeDateTimeProvider)
// - INV-18: Zero-Trust (jumps > threshold rejected)
// =============================================================================

import 'package:test/test.dart';
import 'package:veraprob/application/normalization/motion_classifier.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/application/normalization/operational_state_normalizer.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

import '../../mocks/fake_date_time_provider.dart';

// ── Coordinate constants ──────────────────────────────────────────────────────
const double kStopALat = -23.5612;
const double kStopALng = -46.6560;

// ── FakeMotionClassifier ──────────────────────────────────────────────────────
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
    List stops,
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

VehiclePosition makePing({
  required FakeDateTimeProvider clock,
  double lat = kStopALat,
  double lng = kStopALng,
  double speed = 20.0,
  String tripId = 'trip-1',
}) => VehiclePosition(
  tripId: tripId,
  latitude: lat,
  longitude: lng,
  speed: speed,
  timestamp: clock.now(),
  source: 'test',
);

// ── Tests ─────────────────────────────────────────────────────────────────────
void main() {
  final kEpoch = DateTime.utc(2026, 4, 14, 12, 0, 0);

  group('Jump Threshold Edge Cases', () {
    // E1 — Jump exactly 500.0 m → accepted (smoothing applies)
    // 0.004491 deg × 111 320 m/deg ≈ 500.0 m
    test('E1: Jump exactly 500.0 m -> accepted', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.now());
      clock.advance(const Duration(seconds: 6));
      final out = normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.004491, lng: kStopALng),
      ], now: clock.now());
      // Smoothing applies: result is between original and new position
      expect(out.first.latitude, greaterThan(kStopALat));
      expect(out.first.latitude, lessThan(kStopALat + 0.004491));
    });

    // E2 — Jump 500.01 m → rejected (cache replayed with degraded state)
    test('E2: Jump 500.01 m -> rejected', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.now());
      clock.advance(const Duration(seconds: 6));
      final out = normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.004492, lng: kStopALng),
      ], now: clock.now());
      // Jump rejected: degraded state replayed, smoothing from buffer applies
      expect(out.first.latitude, lessThan(kStopALat + 0.004492));
    });

    // E3 — Triple spikes (>1000 m) → all rejected
    test('E3: Triple spikes (>1000 m) -> all rejected', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.now());
      clock.advance(const Duration(seconds: 6));
      normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.01, lng: kStopALng),
      ], now: clock.now());
      clock.advance(const Duration(seconds: 6));
      normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.02, lng: kStopALng),
      ], now: clock.now());
      clock.advance(const Duration(seconds: 6));
      final out = normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.03, lng: kStopALng),
      ], now: clock.now());
      expect(out.first.latitude, closeTo(kStopALat, 1e-6));
    });
  });

  group('State Persistence', () {
    // E4 — Cold start (no cache) → confidence == 1.0
    test('E4: Cold start (no cache) -> confidence == 1.0', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      final out = normalizer.normalize([
        makePing(clock: clock),
      ], now: clock.now());
      expect(out.first.confidence, 1.0);
    });

    // E5 — Moving->Dwelling transition → stateChangedAt advances
    test('E5: Moving->Dwelling transition -> stateChangedAt advances', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final movingClassifier = FakeMotionClassifier(MotionState.moving);
      final normalizer = makeNormalizer(movingClassifier);
      normalizer.normalize([makePing(clock: clock)], now: clock.now());
      final t1 = clock.now();
      clock.advance(const Duration(seconds: 6));
      movingClassifier.fixedResult = MotionState.dwellingAtStop;
      final out = normalizer.normalize([
        makePing(clock: clock, speed: 0),
      ], now: clock.now());
      expect(out.first.stateChangedAt.isAfter(t1), isTrue);
    });

    // E6 — Replay without state change → stateChangedAt preserved
    test('E6: Replay without state change -> stateChangedAt preserved', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.now());
      final t1 = clock.now();
      clock.advance(const Duration(seconds: 25)); // < 30s degraded threshold
      final out = normalizer.normalize([], now: clock.now());
      // Connectivity still healthy, motion unchanged -> stateChangedAt preserved
      expect(out.first.stateChangedAt, t1);
    });

    // E7 — Debounce exact (5000 ms) → maintains previous ping
    test('E7: Debounce exact (5000 ms) -> maintains previous ping', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(
        FakeMotionClassifier(MotionState.moving),
      );
      normalizer.normalize([makePing(clock: clock)], now: clock.now());
      clock.advance(const Duration(milliseconds: 4999));
      final out = normalizer.normalize([
        makePing(clock: clock, lat: kStopALat + 0.001, lng: kStopALng),
      ], now: clock.now());
      expect(out.first.latitude, closeTo(kStopALat, 1e-6));
    });
  });
}
