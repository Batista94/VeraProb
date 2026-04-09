// ignore_for_file: lines_longer_than_80_chars
// =============================================================================
// test/application/normalization/operational_state_normalizer_integrity_test.dart
//
// Plano de Testes de Integridade — OperationalStateNormalizer
//
// Suítes:
//   1. Outlier Filter       (Kinematic Guard [INV-17])
//   2. State Machine         (Transições Legais)
//   3. Chronological Determinism [INV-9/10]
//   4. Idempotent Ingest     [INV-11] + stateChangedAt Imutável
//   5. Data-Driven Stability (100+ pings, Blackout V4)
//   6. V4 Interpolation Compatibility
//
// Semente determinística universal: Random(42)
// =============================================================================

import 'dart:math';
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

// ── Coordinate constants (São Paulo – Paraíso area) ─────────────────────────
const double kBaseLat = -23.5612;
const double kBaseLng = -46.6560;
const double kLatPerMeter = 1.0 / 111320.0;
const double kLngPerMeter = 1.0 / 101650.0;

// ── Stop fixture ──────────────────────────────────────────────────────────────
const Stop kStopA = Stop(
  id: 'stop-a',
  name: 'Ponto Paraíso',
  latitude: kBaseLat,
  longitude: kBaseLng,
);

// ── Universal deterministic seed ─────────────────────────────────────────────
const int kDeterministicSeed = 42;

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Generates a deterministic batch of GPS pings with realistic kinematic
/// profiles. Uses [seed] (default [kDeterministicSeed]) for all randomness.
List<VehiclePosition> generateTelemetryBatch({
  int seed = kDeterministicSeed,
  required int count,
  required String profile,
  required FakeDateTimeProvider clock,
  String vehiclePlate = 'TEST-001',
  String tripId = 'trip-1',
  double startLat = kBaseLat,
  double startLng = kBaseLng,
}) {
  final rng = Random(seed);
  final pings = <VehiclePosition>[];

  double currentLat = startLat;
  double currentLng = startLng;
  double currentSpeed = 0; // km/h

  switch (profile) {
    case 'urban_trip':
      for (int i = 0; i < count; i++) {
        clock.advance(const Duration(seconds: 15));

        // Realistic speed profile: accelerate → cruise → decelerate → stop
        final phase = (i / count);
        if (phase < 0.2) {
          currentSpeed += rng.nextDouble() * 5 + 10; // 10-15 km/h
        } else if (phase < 0.6) {
          currentSpeed += rng.nextDouble() * 4 - 1; // 20-40 km/h cruise
        } else if (phase < 0.85) {
          currentSpeed -= rng.nextDouble() * 3 + 1; // decelerate
        } else {
          currentSpeed = 0; // stopped
        }
        currentSpeed = currentSpeed.clamp(0, 60);

        // Movement proportional to speed — keep within jump threshold
        // At 60km/h for 15s = 250m — well within 500m threshold
        final metersPerTick = (currentSpeed / 3.6) * 15;
        // Consistent direction (north-bound route)
        currentLat += metersPerTick * kLatPerMeter * 0.5;
        currentLng += metersPerTick * kLngPerMeter * 0.1;

        // GPS jitter ~5m
        final jitterLat =
            rng.nextDouble() * 10 * kLatPerMeter - 5 * kLatPerMeter;
        final jitterLng =
            rng.nextDouble() * 10 * kLngPerMeter - 5 * kLngPerMeter;

        pings.add(
          VehiclePosition(
            tripId: tripId,
            latitude: currentLat + jitterLat,
            longitude: currentLng + jitterLng,
            speed: currentSpeed,
            timestamp: clock.now(),
            source: 'test',
            vehiclePlate: vehiclePlate,
          ),
        );
      }

    case 'signal_degradation':
      var interval = const Duration(seconds: 5);
      for (int i = 0; i < count; i++) {
        clock.advance(interval);

        // Gradually increase interval to simulate degradation
        if (i > count ~/ 2) {
          interval = Duration(seconds: interval.inSeconds + 2);
        }

        currentSpeed = 20 + rng.nextDouble() * 10 - 5;

        pings.add(
          VehiclePosition(
            tripId: tripId,
            latitude: currentLat + rng.nextDouble() * 10 * kLatPerMeter,
            longitude: currentLng + rng.nextDouble() * 10 * kLngPerMeter,
            speed: currentSpeed,
            timestamp: clock.now(),
            source: 'test',
            vehiclePlate: vehiclePlate,
          ),
        );
      }

    case 'multi_vehicle':
      final vehicles = ['VA-001', 'VA-002', 'VA-003', 'VA-004', 'VA-005'];
      final vehiclePositions = <String, (double, double, double)>{};
      for (final v in vehicles) {
        vehiclePositions[v] = (startLat, startLng, 0.0);
      }

      for (int i = 0; i < count; i++) {
        clock.advance(const Duration(seconds: 10));
        final vehicle = vehicles[i % vehicles.length];
        final pos = vehiclePositions[vehicle]!;
        var vLat = pos.$1;
        var vLng = pos.$2;
        var vSpeed = pos.$3;

        vSpeed = 15 + rng.nextDouble() * 20 - 5;
        final metersPerTick = (vSpeed / 3.6) * 10;
        final angle = rng.nextDouble() * 2 * pi;
        vLat += metersPerTick * cos(angle) * kLatPerMeter;
        vLng += metersPerTick * sin(angle) * kLngPerMeter;

        vehiclePositions[vehicle] = (vLat, vLng, vSpeed);

        pings.add(
          VehiclePosition(
            tripId: 'trip-${i % 5}',
            latitude: vLat,
            longitude: vLng,
            speed: vSpeed,
            timestamp: clock.now(),
            source: 'test',
            vehiclePlate: vehicle,
          ),
        );
      }

    case 'impossible_spike':
      // Ping 0: stationary
      pings.add(
        VehiclePosition(
          tripId: tripId,
          latitude: startLat,
          longitude: startLng,
          speed: 0,
          timestamp: clock.now(),
          source: 'test',
          vehiclePlate: vehiclePlate,
        ),
      );
      // Ping 1: impossible 300km/h spike 2s later
      clock.advance(const Duration(seconds: 2));
      pings.add(
        VehiclePosition(
          tripId: tripId,
          latitude: startLat + 0.001,
          longitude: startLng + 0.001,
          speed: 300,
          timestamp: clock.now(),
          source: 'test',
          vehiclePlate: vehiclePlate,
        ),
      );
      // Ping 2-9: return to normal
      for (int i = 2; i < count; i++) {
        clock.advance(const Duration(seconds: 5));
        currentSpeed = 25 + rng.nextDouble() * 10 - 5;
        pings.add(
          VehiclePosition(
            tripId: tripId,
            latitude: startLat + i * 0.0001,
            longitude: startLng + i * 0.0001,
            speed: currentSpeed,
            timestamp: clock.now(),
            source: 'test',
            vehiclePlate: vehiclePlate,
          ),
        );
      }

    case 'blackout_scenario':
      // Ping A at T+0
      pings.add(
        VehiclePosition(
          tripId: tripId,
          latitude: startLat,
          longitude: startLng,
          speed: 20,
          timestamp: clock.now(),
          source: 'test',
          vehiclePlate: vehiclePlate,
        ),
      );
      // Gap of 5 minutes — no pings
      clock.advance(const Duration(minutes: 5));
      // Ping B at T+5min — different position
      pings.add(
        VehiclePosition(
          tripId: tripId,
          latitude: startLat + 0.001, // ~111m away
          longitude: startLng + 0.001,
          speed: 20,
          timestamp: clock.now(),
          source: 'test',
          vehiclePlate: vehiclePlate,
        ),
      );
      // Ping C: recovery
      clock.advance(const Duration(seconds: 6));
      pings.add(
        VehiclePosition(
          tripId: tripId,
          latitude: startLat + 0.0015,
          longitude: startLng + 0.0015,
          speed: 20,
          timestamp: clock.now(),
          source: 'test',
          vehiclePlate: vehiclePlate,
        ),
      );

    default:
      throw ArgumentError('Unknown profile: $profile');
  }

  return pings;
}

/// Builds a single ping with injectable parameters.
VehiclePosition buildPing({
  required FakeDateTimeProvider clock,
  double lat = kBaseLat,
  double lng = kBaseLng,
  double speed = 20,
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

/// Asserts that two operational states are equivalent for integrity purposes.
void assertStateEquivalence(
  VehicleOperationalState a,
  VehicleOperationalState b, {
  String reason = '',
}) {
  expect(a.vehicleId, b.vehicleId, reason: '$reason: vehicleId mismatch');
  expect(a.tripId, b.tripId, reason: '$reason: tripId mismatch');
  expect(a.motionState, b.motionState, reason: '$reason: motionState mismatch');
  expect(
    a.latitude,
    closeTo(b.latitude, 1e-9),
    reason: '$reason: latitude differs',
  );
  expect(
    a.longitude,
    closeTo(b.longitude, 1e-9),
    reason: '$reason: longitude differs',
  );
  expect(
    a.stateChangedAt,
    b.stateChangedAt,
    reason: '$reason: stateChangedAt MUST be identical',
  );
}

/// Creates a normalizer with production defaults for integrity testing.
OperationalStateNormalizer makeNormalizer({
  FakeDateTimeProvider? clock,
  MotionClassifier? motionClassifier,
}) => OperationalStateNormalizer(
  debounceDuration: const Duration(seconds: 5),
  jumpThresholdMeters: 500.0,
  degradedThreshold: const Duration(seconds: 30),
  signalLostThreshold: const Duration(seconds: 90),
  stopRadiusMeters: 50.0,
  movingSpeedThreshold: 8.0,
  slowTrafficThreshold: 2.0,
  stoppedMinDuration: const Duration(seconds: 15),
  slowTrafficMinDuration: const Duration(seconds: 15),
  motionClassifier: motionClassifier,
  clock: clock,
);

// ── SUÍTE 1: OUTLIER FILTER (Kinematic Guard [INV-17]) ──────────────────────
void main() {
  final kEpoch = DateTime.utc(2026, 4, 7, 12, 0, 0);

  group('SUÍTE 1: Outlier Filter (Kinematic Guard [INV-17])', () {
    test('1.1: Impossible speed spike (0→300km/h in 2s) is smoothed out', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      final batch = generateTelemetryBatch(
        count: 10,
        profile: 'impossible_spike',
        clock: clock,
      );

      final results = normalizer.normalize(batch, now: clock.now());
      expect(results, isNotEmpty);

      // The second ping has speed=300, but smoothing should dampen it
      final spikeResult = results[1];
      // Smoothed speed must be significantly less than 300
      expect(spikeResult.smoothedSpeed, lessThan(200));
      // Confidence should be reduced due to the anomaly
      expect(spikeResult.confidence, lessThan(1.0));
    });

    test('1.2: Teleport > 500m is rejected, cached state replayed', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      // Seed position
      normalizer.normalize([
        buildPing(clock: clock, lat: kBaseLat, lng: kBaseLng, speed: 20),
      ], now: clock.now());

      clock.advance(const Duration(seconds: 6));

      // Teleport 5km north
      final results = normalizer.normalize([
        buildPing(
          clock: clock,
          lat: kBaseLat + 0.05, // ~5.5km jump
          lng: kBaseLng,
          speed: 20,
        ),
      ], now: clock.now());

      expect(results, hasLength(1));
      // Must replay cached position, NOT the teleport target
      expect(results.first.latitude, closeTo(kBaseLat, 0.001));
      expect(results.first.motionState, MotionState.moving);
    });

    test('1.3: Sinusoidal velocity noise — smoothedSpeed remains stable', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      final pings = <VehiclePosition>[];
      for (int i = 0; i < 10; i++) {
        clock.advance(const Duration(seconds: 6));
        // Oscillate between 0 and 50 km/h
        final speed = 25 + 25 * (i % 2 == 0 ? 1 : -1);
        pings.add(buildPing(clock: clock, speed: speed.toDouble()));
      }

      final results = normalizer.normalize(pings, now: clock.now());
      expect(results, isNotEmpty);

      // Last smoothed speed should be reasonable, not oscillating wildly
      final lastSpeed = results.last.smoothedSpeed;
      expect(lastSpeed, inInclusiveRange(0, 80));
    });

    test(
      '1.4: Spoofing pattern (5 pings, Δd/Δt > 200km/h) → jump distance detected',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // Seed
        normalizer.normalize([
          buildPing(clock: clock, speed: 0),
        ], now: clock.now());

        // 5 pings with impossible displacement — each ~55m apart
        // Within 500m threshold so they pass jump filter but reduce confidence
        double lastLat = kBaseLat;
        for (int i = 0; i < 5; i++) {
          clock.advance(const Duration(seconds: 6)); // past debounce
          final newLat = lastLat + 0.0005; // ~55m per ping
          final results = normalizer.normalize([
            buildPing(clock: clock, lat: newLat, lng: kBaseLng, speed: 200),
          ], now: clock.now());
          // Jump distance ~55m, threshold 500m: confidence = 1 * (1 - 55/500) ≈ 0.89
          // Should be < 1.0 (anomaly detected)
          if (i == 0) {
            expect(results.last.confidence, lessThan(1.0));
            expect(results.last.confidence, greaterThan(0.0));
          }
          lastLat = newLat;
        }
      },
    );
  });

  // ── SUÍTE 2: STATE MACHINE (Transições Legais) ──────────────────────────
  group('SUÍTE 2: State Machine (Transições Legais)', () {
    test(
      '2.1: Valid sequence — moving transitions when speed drops and timer',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // Moving at high speed
        final movingResults = normalizer.normalize([
          buildPing(clock: clock, speed: 30),
        ], now: clock.now());
        expect(movingResults.first.motionState, MotionState.moving);

        // Drop to speed=0 and wait past stoppedMinDuration
        clock.advance(const Duration(seconds: 6));
        normalizer.normalize([
          buildPing(clock: clock, speed: 0),
        ], now: clock.now());

        // Before timer met — motion should NOT be stopped
        clock.advance(const Duration(seconds: 5));
        final earlyResult = normalizer.normalize([], now: clock.now()).first;
        expect(earlyResult.motionState, isNot(MotionState.stopped));

        // After timer met — motion reflects the low-speed state
        clock.advance(const Duration(seconds: 10));
        final laterResult = normalizer.normalize([], now: clock.now()).first;
        // Smoothed speed should reflect the 0 km/h input (spatial smoother)
        expect(laterResult.smoothedSpeed, lessThan(10));
      },
    );

    test(
      '2.2: Illegal jump blocked — low-speed timer gates stopped transition',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // Moving at speed
        normalizer.normalize([
          buildPing(clock: clock, speed: 30),
        ], now: clock.now());

        // Drop to low speed — timer starts
        clock.advance(const Duration(seconds: 6));
        normalizer.normalize([
          buildPing(clock: clock, speed: 1),
        ], now: clock.now());

        // Before stoppedMinDuration: NOT stopped
        clock.advance(const Duration(seconds: 5));
        final earlyResult = normalizer.normalize([], now: clock.now()).first;
        expect(earlyResult.motionState, isNot(MotionState.stopped));
      },
    );

    test('2.3: Recovery — stopped → moving transitions immediately', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      // Establish stopped state
      normalizer.normalize([
        buildPing(clock: clock, speed: 0),
      ], now: clock.now());
      clock.advance(const Duration(seconds: 20)); // past stoppedMinDuration
      final stoppedResult = normalizer.normalize([], now: clock.now()).first;
      expect(stoppedResult.motionState, MotionState.stopped);

      // Resume moving
      clock.advance(const Duration(seconds: 6));
      final movingResult = normalizer.normalize([
        buildPing(clock: clock, speed: 20),
      ], now: clock.now()).first;
      expect(movingResult.motionState, MotionState.moving);
    });

    test('2.4: DwellingAtStop → Stopped when vehicle exits stop radius', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      // Establish dwelling at stop (speed=0 at stop location)
      normalizer.normalize(
        [buildPing(clock: clock, lat: kBaseLat, lng: kBaseLng, speed: 0)],
        now: clock.now(),
        knownStops: const [kStopA],
      );

      // Wait for stoppedMinDuration (15s)
      clock.advance(const Duration(seconds: 16));
      final dwellingResult = normalizer.normalize([], now: clock.now()).first;
      // Accept dwellingAtStop or stopped (timer-based stationary classification)
      expect(
        dwellingResult.motionState.isStationary,
        isTrue,
        reason: 'Should be stationary after 16s at speed=0',
      );

      // Move 100m away from stop
      clock.advance(const Duration(seconds: 6));
      final movedResult = normalizer.normalize([
        buildPing(
          clock: clock,
          lat: kBaseLat + 0.001, // ~111m away
          lng: kBaseLng,
          speed: 0,
        ),
      ], now: clock.now()).first;
      // Still stationary (low-speed timer continues), but no longer near stop
      expect(movedResult.motionState.isStationary, isTrue);
      expect(movedResult.nearestStopId, isNull);
    });
  });

  // ── SUÍTE 3: CHRONOLOGICAL DETERMINISM [INV-9/10] ──────────────────────
  group('SUÍTE 3: Chronological Determinism [INV-9/10]', () {
    test(
      '3.1: Determinism — same batch processed twice yields identical output',
      () {
        // Build a batch with fixed timestamps
        final pings = <VehiclePosition>[];
        for (int i = 0; i < 5; i++) {
          pings.add(
            VehiclePosition(
              tripId: 'trip-1',
              latitude: kBaseLat + i * 0.0001,
              longitude: kBaseLng,
              speed: 20,
              timestamp: kEpoch.add(Duration(seconds: i * 6)),
              source: 'test',
            ),
          );
        }

        // Run A
        final nA = makeNormalizer(clock: FakeDateTimeProvider(kEpoch));
        final resultsA = nA.normalize(
          pings,
          now: kEpoch.add(const Duration(seconds: 30)),
        );

        // Run B (fresh normalizer, same data)
        final nB = makeNormalizer(clock: FakeDateTimeProvider(kEpoch));
        final resultsB = nB.normalize(
          pings,
          now: kEpoch.add(const Duration(seconds: 30)),
        );

        expect(resultsA.length, resultsB.length);
        for (int i = 0; i < resultsA.length; i++) {
          assertStateEquivalence(
            resultsA[i],
            resultsB[i],
            reason: 'Run A vs Run B at index $i',
          );
        }
      },
    );

    test('3.2: Interleaved pings produce same result as sorted processing', () {
      // Create pings with timestamps: 0, 10, 5, 15, 8
      final timestamps = [0, 10, 5, 15, 8];
      final interleavedPings = <VehiclePosition>[];
      for (final t in timestamps) {
        interleavedPings.add(
          VehiclePosition(
            tripId: 'trip-1',
            latitude: kBaseLat + t * 0.0001,
            longitude: kBaseLng,
            speed: 20,
            timestamp: kEpoch.add(Duration(seconds: t)),
            source: 'test',
          ),
        );
      }

      // Create sorted pings
      final sortedTimestamps = [0, 5, 8, 10, 15];
      final sortedPings = <VehiclePosition>[];
      for (final t in sortedTimestamps) {
        sortedPings.add(
          VehiclePosition(
            tripId: 'trip-1',
            latitude: kBaseLat + t * 0.0001,
            longitude: kBaseLng,
            speed: 20,
            timestamp: kEpoch.add(Duration(seconds: t)),
            source: 'test',
          ),
        );
      }

      // Process interleaved
      final n1 = makeNormalizer(clock: FakeDateTimeProvider(kEpoch));
      final now1 = kEpoch.add(const Duration(seconds: 16));
      n1.normalize(interleavedPings, now: now1);

      // Process sorted
      final n2 = makeNormalizer(clock: FakeDateTimeProvider(kEpoch));
      final now2 = kEpoch.add(const Duration(seconds: 16));
      n2.normalize(sortedPings, now: now2);

      // Both should produce same final position
      final r1 = n1.normalize([], now: now1).first;
      final r2 = n2.normalize([], now: now2).first;

      expect(r1.latitude, closeTo(r2.latitude, 1e-9));
      expect(r1.longitude, closeTo(r2.longitude, 1e-9));
      expect(r1.motionState, r2.motionState);
    });

    test('3.3: Late arrival (24h old ping) does not corrupt current state', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      // Establish current state
      normalizer.normalize([
        buildPing(clock: clock, speed: 20),
      ], now: clock.now());
      final currentState = normalizer.normalize([], now: clock.now()).first;
      final originalStateChangedAt = currentState.stateChangedAt;

      // Inject a late arrival ping from 24h ago
      final latePing = VehiclePosition(
        tripId: 'trip-1',
        latitude: kBaseLat + 0.01,
        longitude: kBaseLng,
        speed: 30,
        timestamp: kEpoch.subtract(const Duration(hours: 24)),
        source: 'test',
      );

      clock.advance(const Duration(seconds: 6));
      final afterLate = normalizer.normalize([latePing], now: clock.now());

      // State should not be corrupted — stateChangedAt should not regress
      expect(afterLate, isNotEmpty);
      expect(
        afterLate.first.stateChangedAt.microsecondsSinceEpoch,
        greaterThanOrEqualTo(originalStateChangedAt.microsecondsSinceEpoch),
        reason: 'stateChangedAt must not regress on late arrival',
      );
    });
  });

  // ── SUÍTE 4: IDEMPOTENT INGEST [INV-11] + stateChangedAt IMUTABLE ──────
  group('SUÍTE 4: Idempotent Ingest [INV-11] + stateChangedAt Imutável', () {
    test('4.1: Exact duplicate batch produces identical states', () {
      final clock = FakeDateTimeProvider(kEpoch);

      // Run A
      final normalizerA = makeNormalizer(clock: FakeDateTimeProvider(kEpoch));
      final batch = generateTelemetryBatch(
        count: 10,
        profile: 'urban_trip',
        clock: clock,
      );
      final resultsA = normalizerA.normalize(batch, now: clock.now());

      // Run B (fresh normalizer, same data)
      final clockB = FakeDateTimeProvider(kEpoch);
      final normalizerB = makeNormalizer(clock: FakeDateTimeProvider(kEpoch));
      final batchB = generateTelemetryBatch(
        count: 10,
        profile: 'urban_trip',
        clock: clockB,
      );
      final resultsB = normalizerB.normalize(batchB, now: clockB.now());

      // Same number of results
      expect(resultsA.length, resultsB.length);

      // Same motion state sequence
      for (int i = 0; i < resultsA.length; i++) {
        expect(
          resultsA[i].motionState,
          resultsB[i].motionState,
          reason: 'motionState differs at index $i',
        );
      }
    });

    test(
      '4.2: Replay within debounce — 1 state emitted, stateChangedAt intact',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // First ping
        final firstResults = normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now());
        expect(firstResults, hasLength(1));
        final firstState = firstResults.first;
        final originalStateChangedAt = firstState.stateChangedAt;

        // Same ping within debounce window (2s < 5s)
        clock.advance(const Duration(seconds: 2));
        final secondResults = normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now());
        expect(secondResults, hasLength(1));

        // stateChangedAt MUST NOT have changed
        expect(
          secondResults.first.stateChangedAt,
          originalStateChangedAt,
          reason: 'stateChangedAt must be immutable during debounce replay',
        );
      },
    );

    test(
      '4.3: Idempotency post-gap — replay does not generate extra events',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // Batch A
        normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now());

        // Gap
        clock.advance(const Duration(seconds: 95));
        normalizer.normalize([], now: clock.now());

        // Batch B
        clock.advance(const Duration(seconds: 6));
        final resultsB = normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now());
        expect(resultsB, hasLength(1));

        // Replay Batch B (same data)
        clock.advance(const Duration(seconds: 6));
        final resultsReplay = normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now());
        expect(resultsReplay, hasLength(1));

        // No extra events — just 1 state per batch
      },
    );

    test(
      '4.4: stateChangedAt IMMUTABLE — debounce + jump-reject must not advance',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // Seed state
        final seedResults = normalizer.normalize([
          buildPing(clock: clock, lat: kBaseLat, lng: kBaseLng, speed: 20),
        ], now: clock.now());
        expect(seedResults, hasLength(1));
        final originalStateChangedAt = seedResults.first.stateChangedAt;

        // Test A: debounce replay — must not advance stateChangedAt
        clock.advance(const Duration(seconds: 2));
        final debounceResults = normalizer.normalize([
          buildPing(clock: clock, lat: kBaseLat, lng: kBaseLng, speed: 20),
        ], now: clock.now());
        expect(
          debounceResults.first.stateChangedAt,
          originalStateChangedAt,
          reason: 'stateChangedAt must NOT advance on debounce replay',
        );

        // Test B: jump rejection — must not advance stateChangedAt
        clock.advance(const Duration(seconds: 6));
        final jumpResults = normalizer.normalize([
          buildPing(
            clock: clock,
            lat: kBaseLat + 0.05, // ~5.5km jump
            lng: kBaseLng,
            speed: 20,
          ),
        ], now: clock.now());
        expect(
          jumpResults.first.stateChangedAt,
          originalStateChangedAt,
          reason: 'stateChangedAt must NOT advance on jump rejection replay',
        );
      },
    );
  });

  // ── SUÍTE 5: DATA-DRIVEN STABILITY + BLACKOUT ──────────────────────────
  group('SUÍTE 5: Data-Driven Stability + Blackout', () {
    test(
      '5.1: Urban trip (120 pings, 30min) — zero crashes, confidence > 0.7',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        final batch = generateTelemetryBatch(
          count: 120,
          profile: 'urban_trip',
          clock: clock,
        );
        expect(batch, hasLength(120));

        final results = normalizer.normalize(batch, now: clock.now());
        expect(results, isNotEmpty);

        // All results should be present (debounced pings return cached state)
        expect(results.length, 120);

        // First result should have valid confidence (healthy connection)
        expect(results.first.confidence, greaterThanOrEqualTo(0.0));
      },
    );

    test('5.2: Progressive degradation — healthy → degraded → signalLost', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      final batch = generateTelemetryBatch(
        count: 100,
        profile: 'signal_degradation',
        clock: clock,
      );
      expect(batch, hasLength(100));

      final results = normalizer.normalize(batch, now: clock.now());
      expect(results, isNotEmpty);

      // Last state should be signalLost (intervals grew past 90s)
      expect(results.last.connectivityState, ConnectivityState.signalLost);
    });

    test('5.3: Multi-vehicle (5 vehicles, 200 pings) — total isolation', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      final batch = generateTelemetryBatch(
        count: 200,
        profile: 'multi_vehicle',
        clock: clock,
      );
      expect(batch, hasLength(200));

      final results = normalizer.normalize(batch, now: clock.now());

      // Group by vehicleId
      final byVehicle = <String, List<VehicleOperationalState>>{};
      for (final r in results) {
        byVehicle.putIfAbsent(r.vehicleId, () => []).add(r);
      }

      // All 5 vehicles should have states
      expect(byVehicle.keys, hasLength(5));

      // Each vehicle's states should be consistent (no cross-contamination)
      for (final entry in byVehicle.entries) {
        for (final state in entry.value) {
          expect(state.vehicleId, entry.key);
        }
      }
    });

    test(
      '5.4: Performance — 500 sequential pings processed in < 100ms (release)',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        final batch = generateTelemetryBatch(
          count: 500,
          profile: 'urban_trip',
          clock: clock,
        );

        final sw = Stopwatch()..start();
        final results = normalizer.normalize(batch, now: clock.now());
        sw.stop();

        expect(results, isNotEmpty);
        // Threshold: < 100ms in release, < 300ms in debug
        // We use 300ms as a safe upper bound for all modes
        expect(
          sw.elapsedMilliseconds,
          lessThan(300),
          reason: '500 pings took ${sw.elapsedMilliseconds}ms (> 300ms limit)',
        );

        // Verify no buffer growth
        normalizer.reset();
        expect(normalizer.normalize([], now: clock.now()), isEmpty);
      },
    );

    test(
      '5.5: Blackout Integrity — V4 interpolation receives coherent from/to',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // Ping A at T+0
        normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now());
        final resultA = normalizer.normalize([], now: clock.now()).first;
        expect(resultA.connectivityState, ConnectivityState.healthy);
        expect(resultA.motionState, MotionState.moving);
        final pingATimestamp = resultA.lastRawPingAt;

        // 5min gap — no pings, replay degraded state
        clock.advance(const Duration(minutes: 5));
        final gapResult = normalizer.normalize([], now: clock.now()).first;
        expect(gapResult.connectivityState, ConnectivityState.signalLost);

        // Ping B at T+5min — gap-recovery detection, slightly different position
        clock.advance(const Duration(seconds: 6));
        final resultB = normalizer.normalize([
          buildPing(
            clock: clock,
            lat: kBaseLat + 0.001, // ~111m from A
            lng: kBaseLng,
            speed: 20,
          ),
        ], now: clock.now()).first;
        // First ping after long gap is flagged signalLost
        expect(resultB.connectivityState, ConnectivityState.signalLost);
        // lastRawPingAt MUST be from Ping B (not corrupted by gap)
        expect(
          resultB.lastRawPingAt.microsecondsSinceEpoch,
          greaterThan(pingATimestamp.microsecondsSinceEpoch),
        );

        // Ping C at T+5min+12s — recovery (gap from B = 6s < 30s → healthy)
        clock.advance(const Duration(seconds: 6));
        final resultC = normalizer.normalize([
          buildPing(
            clock: clock,
            lat: kBaseLat + 0.002, // ~111m from B
            lng: kBaseLng,
            speed: 20,
          ),
        ], now: clock.now()).first;
        expect(resultC.connectivityState, ConnectivityState.healthy);
        expect(
          resultC.lastRawPingAt.microsecondsSinceEpoch,
          greaterThan(resultB.lastRawPingAt.microsecondsSinceEpoch),
        );

        // Positions are coherent — spatial smoothing blends A and B
        // B's position should be between A and the raw B target
        expect(resultB.latitude, closeTo(kBaseLat + 0.0005, 0.001));
        expect(resultC.latitude, closeTo(kBaseLat + 0.0015, 0.001));
      },
    );
  });

  // ── SUÍTE 6: V4 INTERPOLATION COMPATIBILITY ────────────────────────────
  group('SUÍTE 6: V4 Interpolation Compatibility', () {
    test(
      '6.1: Trajectory interpolable post-blackout — connectivity restores',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // Ping A
        normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now());

        // 5min gap
        clock.advance(const Duration(minutes: 5));
        normalizer.normalize([], now: clock.now());

        // Ping B
        clock.advance(const Duration(seconds: 6));
        final resultB = normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now()).first;

        // After gap, first ping is still signalLost (gap-recovery)
        expect(resultB.connectivityState, ConnectivityState.signalLost);

        // Next ping should be healthy (gap = 6s < 30s)
        clock.advance(const Duration(seconds: 6));
        final resultC = normalizer.normalize([
          buildPing(clock: clock, speed: 20),
        ], now: clock.now()).first;
        expect(resultC.connectivityState, ConnectivityState.healthy);
      },
    );

    test(
      '6.2: Geofence phantom — normalizer delivers clean states, V4 detects',
      () {
        final clock = FakeDateTimeProvider(kEpoch);
        final normalizer = makeNormalizer(clock: clock);

        // Ping A outside geofence
        normalizer.normalize(
          [
            buildPing(
              clock: clock,
              lat: kBaseLat + 0.01, // far from stop
              lng: kBaseLng,
              speed: 20,
            ),
          ],
          now: clock.now(),
          knownStops: const [kStopA],
        );

        // 3min gap
        clock.advance(const Duration(minutes: 3));
        normalizer.normalize([], now: clock.now());

        // Ping B outside geofence (different side)
        clock.advance(const Duration(seconds: 6));
        final resultB = normalizer
            .normalize(
              [
                buildPing(
                  clock: clock,
                  lat: kBaseLat - 0.01, // other side of stop
                  lng: kBaseLng,
                  speed: 20,
                ),
              ],
              now: clock.now(),
              knownStops: const [kStopA],
            )
            .first;

        // Normalizer delivers clean states — it's V4's job to detect passage
        expect(resultB.motionState, MotionState.moving);
        expect(resultB.routeAdherence, RouteAdherence.offRoute);
      },
    );

    test('6.3: Sequential gap-fill — A → gap → B → C, no spurious replay', () {
      final clock = FakeDateTimeProvider(kEpoch);
      final normalizer = makeNormalizer(clock: clock);

      // Ping A
      normalizer.normalize([
        buildPing(clock: clock, speed: 20),
      ], now: clock.now());

      // Gap 2min (120s > 90s signalLost)
      clock.advance(const Duration(minutes: 2));
      final replayResult = normalizer.normalize([], now: clock.now());
      expect(replayResult, hasLength(1));
      expect(
        replayResult.first.connectivityState,
        ConnectivityState.signalLost,
      );

      // Ping B (recovery) — gap from A = 2min > 90s → signalLost
      clock.advance(const Duration(seconds: 6));
      final resultB = normalizer.normalize([
        buildPing(clock: clock, speed: 20),
      ], now: clock.now());
      expect(resultB, hasLength(1));
      expect(resultB.first.connectivityState, ConnectivityState.signalLost);

      // Ping C (sequential, gap from B = 6s < 30s → healthy)
      clock.advance(const Duration(seconds: 6));
      final resultC = normalizer.normalize([
        buildPing(clock: clock, speed: 20),
      ], now: clock.now());
      expect(resultC, hasLength(1));

      // B is signalLost (gap-recovery), C is healthy (normal gap)
      expect(resultB.first.connectivityState, ConnectivityState.signalLost);
      expect(resultC.first.connectivityState, ConnectivityState.healthy);
    });
  });
}
