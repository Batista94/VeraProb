// TDD anchor — Phase 10 Workstream 2 (MAVERICK)
// INV-6: PAST_TS must use UTC explicitly — local TZ offset causes false fraud positives.
// INV-15: clock drift sealed at ingest; replay reads stored value.
//
// These tests verify the Dart-side drift logic and UTC correctness contract.
// The TypeScript webhook uses the same threshold (FRAUD_DRIFT_THRESHOLD_S = 300s).

import 'package:flutter_test/flutter_test.dart';

// Mirrors calculateClockDrift from supabase/functions/shared/clock_drift_helper.ts
int calculateClockDrift(int messageUnixTs, int serverUnixTs) {
  return (serverUnixTs - messageUnixTs).round();
}

const int fraudDriftThresholdS = 300; // 5 minutes

void main() {
  group('Clock drift — UTC enforcement (INV-6)', () {
    test(
      'PAST_TS generated via DateTime.now().toUtc() does not cause false positive',
      () {
        // INV-6: UTC explicit. Never use DateTime.now() without .toUtc().
        final serverUtc = DateTime.now().toUtc(); // INV-6: UTC explicit
        final pastTs = serverUtc.subtract(const Duration(seconds: 10));

        final serverUnix = serverUtc.millisecondsSinceEpoch ~/ 1000;
        final messageUnix = pastTs.millisecondsSinceEpoch ~/ 1000;

        final drift = calculateClockDrift(messageUnix, serverUnix);

        // 10s drift is well below 300s threshold — must NOT trigger fraud alert
        expect(
          drift.abs(),
          lessThan(fraudDriftThresholdS),
          reason:
              'Local-TZ offset must not inflate drift into fraud territory. '
              'PAST_TS must use .toUtc().',
        );
      },
    );

    test('drift > 300s triggers fraud threshold', () {
      final serverUtc = DateTime.now().toUtc(); // INV-6: UTC explicit
      final pastTs = serverUtc.subtract(const Duration(seconds: 400));

      final serverUnix = serverUtc.millisecondsSinceEpoch ~/ 1000;
      final messageUnix = pastTs.millisecondsSinceEpoch ~/ 1000;

      final drift = calculateClockDrift(messageUnix, serverUnix);
      expect(drift.abs(), greaterThan(fraudDriftThresholdS));
    });

    test('device 10s ahead of server: negative drift, below threshold', () {
      final serverUtc = DateTime.now().toUtc(); // INV-6: UTC explicit
      final futureTs = serverUtc.add(const Duration(seconds: 10));

      final serverUnix = serverUtc.millisecondsSinceEpoch ~/ 1000;
      final messageUnix = futureTs.millisecondsSinceEpoch ~/ 1000;

      final drift = calculateClockDrift(messageUnix, serverUnix);
      expect(drift, isNegative);
      expect(drift.abs(), lessThan(fraudDriftThresholdS));
    });

    test('drift calculation is symmetric (server - message)', () {
      final baseUtc = DateTime.utc(
        2026,
        4,
        24,
        12,
        0,
        0,
      ); // INV-6: UTC explicit
      final serverUnix = baseUtc.millisecondsSinceEpoch ~/ 1000;
      final messageUnix = serverUnix - 120; // device 2min behind server

      final drift = calculateClockDrift(messageUnix, serverUnix);
      expect(drift, equals(120)); // positive: device behind
    });
  });

  group('Clock drift — fraud boundary', () {
    test('299s drift: NOT fraud', () {
      const server = 1_000_000;
      const message = server - 299;
      expect(
        calculateClockDrift(message, server).abs(),
        lessThan(fraudDriftThresholdS),
      );
    });

    test('300s drift: IS fraud boundary (exact threshold)', () {
      const server = 1_000_000;
      const message = server - 300;
      // At exactly 300s the webhook fires alert (drift > FRAUD_DRIFT_THRESHOLD_S uses >)
      // calculateClockDrift = 300 which equals threshold — webhook uses > so not triggered
      expect(
        calculateClockDrift(message, server),
        equals(fraudDriftThresholdS),
      );
    });

    test('301s drift: IS fraud', () {
      const server = 1_000_000;
      const message = server - 301;
      expect(
        calculateClockDrift(message, server).abs(),
        greaterThan(fraudDriftThresholdS),
      );
    });
  });
}
