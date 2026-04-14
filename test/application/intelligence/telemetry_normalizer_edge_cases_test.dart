// ignore_for_file: lines_longer_than_80_chars
import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';

void main() {
  group('TelemetryNormalizer - Spoofing Detection Edge Cases', () {
    late TelemetryNormalizer normalizer;

    setUp(() {
      normalizer = TelemetryNormalizer(
        maxAccuracyMeters: 50.0,
        maxImpliedSpeedKmh: 120.0,
      );
    });

    test('EDGE-1: Rejects ping with unrealistic accuracy (stdDev < 0.001)', () {
      // Emulator/spoofed GPS typically reports impossibly precise coordinates
      final ping = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 0.0005, // Unrealistic precision (< 1mm)
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      final result = normalizer.processPing(ping);

      // Should reject due to impossibly low accuracy
      expect(result, isNull);
    });

    test('EDGE-2: Accepts ping with realistic GPS accuracy (5-50m)', () {
      final ping = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0, // Realistic consumer GPS
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      final result = normalizer.processPing(ping);

      expect(result, isNotNull);
      expect(result!.latitude, -23.550520);
    });

    test('EDGE-3: Rejects ping with accuracy > maxAccuracyMeters', () {
      final ping = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 100.0, // Exceeds 50m threshold
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      final result = normalizer.processPing(ping);

      expect(result, isNull);
    });

    test('EDGE-4: Detects impossible jump (teleportation attack)', () {
      // First ping: São Paulo
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      // Second ping: Rio de Janeiro (430km away, 1 second later)
      final ping2 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -22.906847,
        longitude: -43.172896,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 0, 1), // 1 second later
      );

      final result1 = normalizer.processPing(ping1);
      expect(result1, isNotNull);

      final result2 = normalizer.processPing(ping2);
      // Should reject due to impossible speed (430km in 1 second)
      expect(result2, isNull);
    });

    test('EDGE-5: Accepts gradual movement within speed limits', () {
      // First ping
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      // Second ping: 1km away, 60 seconds later (60 km/h)
      final ping2 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.541520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 60.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 1), // 60 seconds later
      );

      final result1 = normalizer.processPing(ping1);
      expect(result1, isNotNull);

      final result2 = normalizer.processPing(ping2);
      expect(result2, isNotNull);
    });

    test('EDGE-6: Rejects same timestamp with significant movement', () {
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      // Same timestamp but 10m away (impossible)
      final ping2 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550610,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 0), // Same timestamp
      );

      final result1 = normalizer.processPing(ping1);
      expect(result1, isNotNull);

      final result2 = normalizer.processPing(ping2);
      // Should reject due to movement with zero time delta
      expect(result2, isNull);
    });

    test('EDGE-7: Multiple vehicles tracked independently', () {
      final ping1v1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      final ping1v2 = RawTelemetryPing(
        vehicleId: 'v2',
        tripId: 't2',
        latitude: -22.906847,
        longitude: -43.172896,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      final result1 = normalizer.processPing(ping1v1);
      final result2 = normalizer.processPing(ping1v2);

      // Both should be accepted (different vehicles)
      expect(result1, isNotNull);
      expect(result2, isNotNull);
    });

    test('EDGE-8: State cleared between test runs', () {
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.550520,
        longitude: -46.633308,
        heading: 90.0,
        speed: 30.0,
        accuracy: 15.0,
        timestamp: DateTime.utc(2026, 4, 14, 18, 0),
      );

      normalizer.processPing(ping1);
      normalizer.clearState();

      // After clear, should accept same ping again (no jump detection)
      final result = normalizer.processPing(ping1);
      expect(result, isNotNull);
    });
  });
}
