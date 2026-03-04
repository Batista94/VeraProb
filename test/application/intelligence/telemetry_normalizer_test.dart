import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/application/intelligence/telemetry_normalizer.dart';
import 'package:busflow/domain/entities/raw_telemetry_ping.dart';
import 'package:busflow/domain/entities/vehicle_position.dart';

void main() {
  group('TelemetryNormalizer (The Purgatory)', () {
    late TelemetryNormalizer normalizer;

    setUp(() {
      normalizer = TelemetryNormalizer(
        maxAccuracyMeters: 50.0,
        maxImpliedSpeedKmh: 120.0, // Absurd speed jump threshold
      );
    });

    test('Discards ping with terrible accuracy', () {
      final badPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.55,
        longitude: -46.63,
        accuracy: 100.0, // Terribe GPS precision
        speed: 10.0,
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      final result = normalizer.processPing(badPing);
      expect(result, isNull);
    });

    test('Accepts first good ping', () {
      final goodPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.55,
        longitude: -46.63,
        accuracy: 10.0, // Great precision
        speed: 10.0,
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      final result = normalizer.processPing(goodPing);
      expect(result, isA<VehiclePosition>());
      expect(result!.latitude, -23.55);
    });

    test('Discards ping implying impossible speed jump (Haversine jump)', () {
      final time = DateTime.now();

      final firstPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.55, // Origin
        longitude: -46.63,
        accuracy: 10.0,
        speed: 15.0,
        heading: 90.0,
        timestamp: time,
      );

      // Register the first ping
      normalizer.processPing(firstPing);

      // 5 seconds later, jump 10km away. This implies a speed of 7200 km/h (impossible)
      final impossibleJumpPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.45, // Big jump
        longitude: -46.63,
        accuracy: 10.0, // GPS says it's accurate, but physics says no
        speed: 15.0,
        heading: 90.0,
        timestamp: time.add(const Duration(seconds: 5)),
      );

      final result = normalizer.processPing(impossibleJumpPing);
      expect(result, isNull); // Filtered out!
    });

    test('Accepts valid sequential pings', () {
      final time = DateTime.now();

      final firstPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5500,
        longitude: -46.6300,
        accuracy: 10.0,
        speed: 10.0, // ~36km/h
        heading: 90.0,
        timestamp: time,
      );

      normalizer.processPing(firstPing);

      // 10 seconds later, moved a bit (100 meters east approx)
      final secondPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5500,
        longitude: -46.6290, // Valid close distance
        accuracy: 10.0,
        speed: 10.0,
        heading: 90.0,
        timestamp: time.add(const Duration(seconds: 10)),
      );

      final result = normalizer.processPing(secondPing);
      expect(result, isA<VehiclePosition>());
    });

    // --- QA Playbook: Módulo 15 Testes de Tolerância a Poison Pills ---

    test(
      'QA Módulo 15 - Rejects time-travel glitch (moved 100m in 0 seconds)',
      () {
        final time0 = DateTime.utc(2026, 3, 1, 10, 0, 0);

        final ping1 = RawTelemetryPing(
          vehicleId: 'glitch-bus',
          tripId: 'trip-1',
          latitude: -23.550500,
          longitude: -46.633300,
          heading: 0,
          speed: 20,
          accuracy: 5.0,
          timestamp: time0,
        );

        normalizer.processPing(ping1);

        // Exactly same timestamp, but latitude noticeably changed
        final ping2 = RawTelemetryPing(
          vehicleId: 'glitch-bus',
          tripId: 'trip-1',
          latitude: -23.551500, // Roughly 111 meters away
          longitude: -46.633300,
          heading: 0,
          speed: 20,
          accuracy: 5.0,
          timestamp: time0, // SAME TIMESTAMP
        );

        final result = normalizer.processPing(ping2);
        expect(result, isNull);
      },
    );
  });
}
