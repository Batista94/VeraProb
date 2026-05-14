import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/application/intelligence/ping_classification.dart';
import 'package:veraprob/application/intelligence/telemetry_normalizer.dart';
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';

void main() {
  group('TelemetryNormalizer - INV-18 Zero-Trust Spoofing Detection', () {
    late TelemetryNormalizer normalizer;

    setUp(() {
      normalizer = TelemetryNormalizer(
        maxAccuracyMeters: 50.0,
        maxImpliedSpeedKmh: 120.0,
      );
    });

    test(
      'EDGE CASE: Rejects ping with unrealistic accuracy (emulator signature)',
      () {
        // Emulators often report stdDev < 0.001 (impossible for real GPS)
        final suspiciousPing = RawTelemetryPing(
          vehicleId: 'v1',
          tripId: 't1',
          latitude: -23.5505,
          longitude: -46.6333,
          accuracy: 0.0005, // Unrealistic precision
          heading: 90.0,
          speed: 50.0,
          timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
        );

        final result = normalizer.processPing(suspiciousPing);

        // INV-18: Reject telemetry with emulator-like precision
        expect(result, isNull, reason: 'Emulator signature detected');
      },
    );

    test('EDGE CASE: Accepts ping with realistic GPS accuracy', () {
      final validPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 15.0, // Realistic GPS accuracy
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      final result = normalizer.processPing(validPing);

      expect(result, isNotNull);
      expect(result!.latitude, -23.5505);
      expect(result.longitude, -46.6333);
    });

    test('EDGE CASE: Rejects impossible speed jump (teleportation)', () {
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      // Accept first ping
      final result1 = normalizer.processPing(ping1);
      expect(result1, isNotNull);

      // Second ping 10 seconds later, 5km away (1800 km/h implied speed)
      final ping2 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5000, // ~6km north
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0, 10).toUtc(),
      );

      final result2 = normalizer.processPing(ping2);

      // INV-18: Reject physically impossible jump
      expect(result2, isNull, reason: 'Impossible speed detected');
    });

    test('EDGE CASE: Accepts realistic speed progression', () {
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      normalizer.processPing(ping1);

      // 100 meters in 10 seconds = 36 km/h (realistic)
      final ping2 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5515, // ~100m north
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0, 10).toUtc(),
      );

      final result2 = normalizer.processPing(ping2);

      expect(result2, isNotNull);
      expect(result2!.latitude, -23.5515);
    });

    test('EDGE CASE: Rejects same timestamp with significant movement', () {
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      normalizer.processPing(ping1);

      // Same timestamp but moved 10 meters (impossible glitch)
      final ping2 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5506, // ~10m away
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(), // Same timestamp
      );

      final result2 = normalizer.processPing(ping2);

      expect(result2, isNull, reason: 'Same timestamp with movement');
    });

    test('EDGE CASE: Accepts same timestamp with minimal movement', () {
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      normalizer.processPing(ping1);

      // Same timestamp, moved 2 meters (GPS jitter, acceptable)
      final ping2 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.55052, // ~2m away
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      final result2 = normalizer.processPing(ping2);

      expect(result2, isNotNull);
    });

    test('EDGE CASE: Rejects ping exceeding accuracy threshold', () {
      final inaccuratePing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 100.0, // Exceeds 50m threshold
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      final result = normalizer.processPing(inaccuratePing);

      expect(result, isNull, reason: 'Accuracy exceeds threshold');
    });

    test('EDGE CASE: Handles multiple vehicles independently', () {
      final v1ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      final v2ping1 = RawTelemetryPing(
        vehicleId: 'v2',
        tripId: 't2',
        latitude: -22.9068,
        longitude: -43.1729,
        accuracy: 15.0,
        heading: 180.0,
        speed: 60.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      final result1 = normalizer.processPing(v1ping1);
      final result2 = normalizer.processPing(v2ping1);

      expect(result1, isNotNull);
      expect(result2, isNotNull);
      expect(result1!.tripId, 't1');
      expect(result2!.tripId, 't2');
    });

    test('EDGE CASE: clearState resets internal tracking', () {
      final ping1 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      normalizer.processPing(ping1);
      normalizer.clearState();

      // After clear, impossible jump should be accepted (no previous ping)
      final ping2 = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5000, // 6km away
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0, 10).toUtc(),
      );

      final result2 = normalizer.processPing(ping2);

      expect(result2, isNotNull, reason: 'State cleared, no previous ping');
    });

    test('EDGE CASE: Haversine distance calculation accuracy', () {
      // Known distance: São Paulo to Rio de Janeiro ~360km
      final spPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -23.5505,
        longitude: -46.6333,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 18, 0).toUtc(),
      );

      normalizer.processPing(spPing);

      final rjPing = RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: -22.9068,
        longitude: -43.1729,
        accuracy: 15.0,
        heading: 90.0,
        speed: 50.0,
        timestamp: DateTime(2026, 4, 14, 19, 0).toUtc(), // 1 hour later
      );

      final result = normalizer.processPing(rjPing);

      // 360km in 1 hour = 360 km/h (exceeds 120 km/h threshold)
      expect(result, isNull, reason: 'Exceeds max speed threshold');
    });
  });

  group('TelemetryNormalizer.classifyPing — auditable rejection reasons', () {
    late TelemetryNormalizer normalizer;

    setUp(() {
      normalizer = TelemetryNormalizer(
        maxAccuracyMeters: 50.0,
        maxImpliedSpeedKmh: 120.0,
      );
    });

    RawTelemetryPing ping({
      double latitude = -23.5505,
      double longitude = -46.6333,
      double accuracy = 15.0,
      DateTime? timestamp,
    }) {
      return RawTelemetryPing(
        vehicleId: 'v1',
        tripId: 't1',
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        heading: 90.0,
        speed: 50.0,
        timestamp: timestamp ?? DateTime(2026, 4, 14, 18, 0).toUtc(),
      );
    }

    test('PingAccepted carrega a posição limpa para ping válido', () {
      final result = normalizer.classifyPing(ping());

      expect(result, isA<PingAccepted>());
      expect((result as PingAccepted).position.latitude, -23.5505);
    });

    test('lowAccuracy quando accuracy excede o limite', () {
      final result = normalizer.classifyPing(ping(accuracy: 100.0));

      expect(result, isA<PingRejected>());
      expect((result as PingRejected).reason, PingRejectionReason.lowAccuracy);
    });

    test(
      'emulatorSignature quando accuracy abaixo do piso físico de ruído',
      () {
        final result = normalizer.classifyPing(ping(accuracy: 0.0005));

        expect(result, isA<PingRejected>());
        expect(
          (result as PingRejected).reason,
          PingRejectionReason.emulatorSignature,
        );
      },
    );

    test('impossibleSpeedJump em salto físico impossível entre pings', () {
      normalizer.classifyPing(ping());

      final result = normalizer.classifyPing(
        ping(
          latitude: -23.5000, // ~6 km north
          timestamp: DateTime(2026, 4, 14, 18, 0, 10).toUtc(),
        ),
      );

      expect(result, isA<PingRejected>());
      expect(
        (result as PingRejected).reason,
        PingRejectionReason.impossibleSpeedJump,
      );
    });

    test('sameTimestampMovement em deslocamento com timestamp idêntico', () {
      normalizer.classifyPing(ping());

      final result = normalizer.classifyPing(
        ping(latitude: -23.5506), // ~10 m away, same timestamp
      );

      expect(result, isA<PingRejected>());
      expect(
        (result as PingRejected).reason,
        PingRejectionReason.sameTimestampMovement,
      );
    });
  });
}
