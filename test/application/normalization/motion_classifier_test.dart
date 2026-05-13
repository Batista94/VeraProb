// ignore_for_file: lines_longer_than_80_chars
// =============================================================================
// test/application/normalization/motion_classifier_test.dart
//
// 100% branch coverage for MotionClassifier.
//
// Coordinate geometry (haversine-exact, São Paulo – Paraíso area):
//   kStopALat/Lng  = (-23.5612,    -46.6560)  — Ponto Paraíso (reference stop)
//   kStopBLat/Lng  = (-23.5593982, -46.6560)  — ~200 m north of A
//   kVehicle30mLat = -23.5609297              — ~30 m north of A (inside 50 m radius)
//   kVehicle80mLat = -23.5604793              — ~80 m north of A (outside 50 m radius)
//
//   Vehicle at kVehicle30mLat â†’ dist_A â‰ˆ 30 m (inside), dist_B â‰ˆ 170 m (outside)
//   Vehicle at kVehicle80mLat â†’ dist_A â‰ˆ 80 m (outside), dist_B â‰ˆ 120 m (outside)
// =============================================================================

import 'package:test/test.dart';
import 'package:veraprob/application/normalization/motion_classifier.dart';
import 'package:veraprob/application/normalization/models/motion_state.dart';
import 'package:veraprob/domain/entities/stop.dart';

import '../../mocks/fake_date_time_provider.dart';

// ── Shared coordinate constants ───────────────────────────────────────────────

/// Reference stop: Ponto Paraíso, Av. Brigadeiro Luís Antônio, São Paulo.
const double kStopALat = -23.5612;
const double kStopALng = -46.6560;

/// Second stop ~200 m north of A.
const double kStopBLat = -23.5593982;
const double kStopBLng = -46.6560;

/// Vehicle position ~30 m north of Stop A â†’ inside 50 m radius of A.
const double kVehicle30mLat = -23.5609297;

/// Vehicle position ~80 m north of Stop A â†’ outside 50 m radius of all stops.
const double kVehicle80mLat = -23.5604793;

const double kBaseLng = -46.6560;

// ── Canonical stop fixtures ───────────────────────────────────────────────────

const Stop kStopA = Stop(
  id: 'stop-a',
  name: 'Ponto Paraíso',
  latitude: kStopALat,
  longitude: kStopALng,
);

const Stop kStopB = Stop(
  id: 'stop-b',
  name: 'Ponto Norte',
  latitude: kStopBLat,
  longitude: kStopBLng,
);

// ── Factory ───────────────────────────────────────────────────────────────────

MotionClassifier makeClassifier() => MotionClassifier(
  movingSpeedThreshold: 8.0,
  slowTrafficThreshold: 2.0,
  stoppedMinDuration: const Duration(seconds: 15),
  slowTrafficMinDuration: const Duration(seconds: 15),
  stopRadiusMeters: 50.0,
);

void main() {
  final kEpoch = DateTime.utc(2026, 4, 7, 12, 0, 0);

  // ── classifyMotion ────────────────────────────────────────────────────────
  group('classifyMotion', () {
    late MotionClassifier classifier;
    late FakeDateTimeProvider clock;

    setUp(() {
      classifier = makeClassifier();
      clock = FakeDateTimeProvider(kEpoch);
    });

    // B1 — speed above movingSpeedThreshold, key was never in map
    test(
      'B1: returns moving and does not insert key when speed > movingSpeedThreshold '
      '(key was never in map)',
      () {
        final result = classifier.classifyMotion(
          'v1',
          10.0, // > 8.0 km/h
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        expect(result, MotionState.moving);

        // Confirm no key was inserted: a subsequent fast call must still return moving
        final result2 = classifier.classifyMotion(
          'v1',
          10.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        expect(result2, MotionState.moving);
      },
    );

    // B2 — speed above movingSpeedThreshold WITH a pre-existing map entry
    test(
      'B2: removes existing low-speed key when speed > movingSpeedThreshold',
      () {
        // Seed a low-speed entry for v2 at t0
        classifier.classifyMotion(
          'v2',
          1.0, // <= slowTrafficThreshold â†’ key inserted
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );

        // Vehicle is now fast â†’ key must be removed
        final result = classifier.classifyMotion(
          'v2',
          10.0, // > movingSpeedThreshold
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        expect(result, MotionState.moving);

        // After removal, advancing time and going slow again re-inserts a fresh
        // timestamp, so duration is 0 â†’ moving (not stopped).
        clock.advance(const Duration(seconds: 20));
        final resultAfterReEntry = classifier.classifyMotion(
          'v2',
          1.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        // 0 s elapsed since fresh insert < stoppedMinDuration(15 s) â†’ moving
        expect(resultAfterReEntry, MotionState.moving);
      },
    );

    // B3 — speed <= movingSpeedThreshold, key NOT yet in map
    test(
      'B3: inserts key with current timestamp when first entering low-speed state',
      () {
        // Fresh classifier, v3 never seen. Duration = 0 < stoppedMinDuration â†’ moving.
        final result = classifier.classifyMotion(
          'v3',
          1.0, // <= slowTrafficThreshold
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        expect(result, MotionState.moving);
      },
    );

    // B4 — speed <= movingSpeedThreshold, key ALREADY in map (timestamp preserved)
    test(
      'B4: putIfAbsent preserves existing timestamp on second low-speed call',
      () {
        final t0 = clock.nowUtc();

        // First call: inserts t0
        classifier.classifyMotion(
          'v4',
          1.0,
          (kStopALat, kStopALng),
          const [],
          t0,
        );

        // Advance 20 s — if putIfAbsent overwrote the key, duration would be 0
        // and the result would be moving instead of stopped.
        clock.advance(const Duration(seconds: 20));
        final result = classifier.classifyMotion(
          'v4',
          1.0,
          (kStopALat, kStopALng),
          const [], // no stops â†’ stopped when duration >= threshold
          clock.nowUtc(),
        );
        // 20 s >= 15 s stoppedMinDuration â†’ stopped (proves timestamp was NOT reset)
        expect(result, MotionState.stopped);
      },
    );

    // B5 — speed <= slowTrafficThreshold, duration < stoppedMinDuration
    test(
      'B5: returns moving when speed <= slowTrafficThreshold but duration < stoppedMinDuration',
      () {
        classifier.classifyMotion(
          'v5',
          1.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );

        clock.advance(const Duration(seconds: 5)); // 5 s < 15 s
        final result = classifier.classifyMotion(
          'v5',
          0.0, // exactly zero — definitely <= slowTrafficThreshold
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        expect(result, MotionState.moving);
      },
    );

    // B6 — speed <= slowTrafficThreshold, duration >= stoppedMinDuration, no near stop
    test(
      'B6: returns stopped when stationary long enough with no stop within radius',
      () {
        classifier.classifyMotion(
          'v6',
          1.0,
          (kVehicle80mLat, kBaseLng),
          const [],
          clock.nowUtc(),
        );

        clock.advance(const Duration(seconds: 15)); // exactly at boundary
        final result = classifier.classifyMotion(
          'v6',
          0.0,
          (kVehicle80mLat, kBaseLng), // ~80 m from Stop A — outside 50 m radius
          [kStopA],
          clock.nowUtc(),
        );
        expect(result, MotionState.stopped);
      },
    );

    // B7 — speed <= slowTrafficThreshold, duration >= stoppedMinDuration, stop within radius
    test(
      'B7: returns dwellingAtStop when stationary long enough and within stop radius',
      () {
        classifier.classifyMotion(
          'v7',
          1.0,
          (kVehicle30mLat, kBaseLng),
          const [],
          clock.nowUtc(),
        );

        clock.advance(const Duration(seconds: 16));
        final result = classifier.classifyMotion(
          'v7',
          0.0,
          (kVehicle30mLat, kBaseLng), // ~30 m from Stop A — inside 50 m radius
          [kStopA],
          clock.nowUtc(),
        );
        expect(result, MotionState.dwellingAtStop);
      },
    );

    // B8 — slowTrafficThreshold < speed <= movingSpeedThreshold,
    //      duration >= slowTrafficMinDuration
    test('B8: returns slowTraffic when in middle speed band long enough', () {
      classifier.classifyMotion(
        'v8',
        5.0, // > 2.0 (slow) AND <= 8.0 (moving)
        (kStopALat, kStopALng),
        const [],
        clock.nowUtc(),
      );

      clock.advance(
        const Duration(seconds: 15),
      ); // exactly at slowTrafficMinDuration
      final result = classifier.classifyMotion(
        'v8',
        5.0,
        (kStopALat, kStopALng),
        const [],
        clock.nowUtc(),
      );
      expect(result, MotionState.slowTraffic);
    });

    // B9 — slowTrafficThreshold < speed <= movingSpeedThreshold,
    //      duration < slowTrafficMinDuration
    test(
      'B9: returns moving when in middle speed band but not long enough',
      () {
        classifier.classifyMotion(
          'v9',
          5.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );

        clock.advance(const Duration(seconds: 5)); // 5 s < 15 s
        final result = classifier.classifyMotion(
          'v9',
          5.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        expect(result, MotionState.moving);
      },
    );
  });

  // ── _findNearestStop (via classifyMotion) ─────────────────────────────────
  group('_findNearestStop via classifyMotion', () {
    late MotionClassifier classifier;
    late FakeDateTimeProvider clock;

    setUp(() {
      classifier = makeClassifier();
      clock = FakeDateTimeProvider(kEpoch);
    });

    /// Prime the low-speed timer for [vehicleId] so that the next call
    /// will have duration >= stoppedMinDuration (15 s).
    void primeTimer(String vehicleId, (double, double) position) {
      classifier.classifyMotion(
        vehicleId,
        0.0,
        position,
        const [],
        clock.nowUtc(),
      );
      clock.advance(const Duration(seconds: 16));
    }

    // B10 — empty stop list
    test('B10: returns stopped when stops list is empty', () {
      primeTimer('vA', (kVehicle80mLat, kBaseLng));
      final result = classifier.classifyMotion(
        'vA',
        0.0,
        (kVehicle30mLat, kBaseLng), // position irrelevant — no stops to check
        const [],
        clock.nowUtc(),
      );
      expect(result, MotionState.stopped);
    });

    // B11 — single stop, distance > radius
    test(
      'B11: returns stopped when the only stop is outside radius (~80 m > 50 m)',
      () {
        primeTimer('vB', (kVehicle80mLat, kBaseLng));
        final result = classifier.classifyMotion(
          'vB',
          0.0,
          (kVehicle80mLat, kBaseLng), // ~80 m from Stop A
          [kStopA],
          clock.nowUtc(),
        );
        expect(result, MotionState.stopped);
      },
    );

    // B12 — single stop, distance <= radius
    test(
      'B12: returns dwellingAtStop when the only stop is inside radius (~30 m < 50 m)',
      () {
        primeTimer('vC', (kVehicle30mLat, kBaseLng));
        final result = classifier.classifyMotion(
          'vC',
          0.0,
          (kVehicle30mLat, kBaseLng), // ~30 m from Stop A
          [kStopA],
          clock.nowUtc(),
        );
        expect(result, MotionState.dwellingAtStop);
      },
    );

    // B13 — multiple stops, closer one inside radius wins; list order must not matter
    test('B13: picks closer stop (A, ~30 m) over farther stop (B, ~170 m) '
        'even when B appears first in the list', () {
      primeTimer('vD', (kVehicle30mLat, kBaseLng));
      // Deliberately pass B before A to prove loop finds the true minimum.
      final result = classifier.classifyMotion(
        'vD',
        0.0,
        (kVehicle30mLat, kBaseLng),
        [kStopB, kStopA], // B first — reversed order
        clock.nowUtc(),
      );
      expect(result, MotionState.dwellingAtStop);
    });

    // B14 — multiple stops, closest still outside radius
    test(
      'B14: returns stopped when multiple stops present but nearest is still outside radius',
      () {
        // kVehicle80mLat: dist_A â‰ˆ 80 m, dist_B â‰ˆ 120 m — both > 50 m
        primeTimer('vE', (kVehicle80mLat, kBaseLng));
        final result = classifier.classifyMotion(
          'vE',
          0.0,
          (kVehicle80mLat, kBaseLng),
          [kStopA, kStopB],
          clock.nowUtc(),
        );
        expect(result, MotionState.stopped);
      },
    );
  });

  // ── removeKey ──────────────────────────────────────────────────────────────
  group('removeKey', () {
    late MotionClassifier classifier;
    late FakeDateTimeProvider clock;

    setUp(() {
      classifier = makeClassifier();
      clock = FakeDateTimeProvider(kEpoch);
    });

    // B15a — removeKey on existing key resets the timer
    test(
      'B15a: removeKey on existing key causes next slow-speed call to use a fresh timestamp',
      () {
        // Seed key at t0
        classifier.classifyMotion(
          'vR',
          1.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );

        // Advance beyond stoppedMinDuration
        clock.advance(const Duration(seconds: 20));

        // Remove the key
        classifier.removeKey('vR');

        // Re-classify: new key inserted at clock.nowUtc(), duration = 0 â†’ moving
        final result = classifier.classifyMotion(
          'vR',
          0.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        expect(result, MotionState.moving);
      },
    );

    // B15b — removeKey on a key that was never inserted must not throw
    test('B15b: removeKey on a missing key does not throw', () {
      expect(
        () => classifier.removeKey('nonexistent-vehicle'),
        returnsNormally,
      );
    });
  });

  // ── reset ──────────────────────────────────────────────────────────────────
  group('reset', () {
    late MotionClassifier classifier;
    late FakeDateTimeProvider clock;

    setUp(() {
      classifier = makeClassifier();
      clock = FakeDateTimeProvider(kEpoch);
    });

    // B16 — reset clears all accumulated state across multiple vehicles
    test(
      'B16: reset clears all low-speed timers so every vehicle starts fresh',
      () {
        final t0 = clock.nowUtc();

        // Seed two vehicles
        classifier.classifyMotion(
          'vX',
          1.0,
          (kStopALat, kStopALng),
          const [],
          t0,
        );
        classifier.classifyMotion(
          'vY',
          1.0,
          (kStopALat, kStopALng),
          const [],
          t0,
        );

        // Advance well past stoppedMinDuration
        clock.advance(const Duration(seconds: 20));

        // Confirm they would reach stopped state without reset
        expect(
          classifier.classifyMotion(
            'vX',
            0.0,
            (kStopALat, kStopALng),
            const [],
            clock.nowUtc(),
          ),
          MotionState.stopped,
        );

        // Reset wipes all state
        classifier.reset();

        // Both vehicles re-insert a fresh timestamp at clock.nowUtc() â†’ duration = 0 â†’ moving
        final afterResetX = classifier.classifyMotion(
          'vX',
          0.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        final afterResetY = classifier.classifyMotion(
          'vY',
          0.0,
          (kStopALat, kStopALng),
          const [],
          clock.nowUtc(),
        );
        expect(afterResetX, MotionState.moving);
        expect(afterResetY, MotionState.moving);
      },
    );
  });
}
