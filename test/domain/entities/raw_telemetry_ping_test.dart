import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/raw_telemetry_ping.dart';

void main() {
  group('RawTelemetryPing', () {
    final ts = DateTime.utc(2026, 3, 25, 12, 0, 0);

    RawTelemetryPing buildPing({
      String vehicleId = 'v-001',
      String tripId = 'trip-abc',
      double latitude = -23.5505,
      double longitude = -46.6333,
      double accuracy = 5.0,
      double speed = 10.0,
      double heading = 90.0,
      DateTime? timestamp,
    }) => RawTelemetryPing(
      vehicleId: vehicleId,
      tripId: tripId,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
      heading: heading,
      timestamp: timestamp ?? ts,
    );

    test('fromJson parses all fields', () {
      final json = {
        'vehicle_id': 'v-123',
        'trip_id': 'trip-xyz',
        'latitude': -23.5505,
        'longitude': -46.6333,
        'accuracy': 3.5,
        'speed': 8.3,
        'heading': 180.0,
        'timestamp': ts.toIso8601String(),
      };
      final ping = RawTelemetryPing.fromJson(json);
      expect(ping.vehicleId, 'v-123');
      expect(ping.tripId, 'trip-xyz');
      expect(ping.latitude, -23.5505);
      expect(ping.longitude, -46.6333);
      expect(ping.accuracy, 3.5);
      expect(ping.speed, 8.3);
      expect(ping.heading, 180.0);
      expect(ping.timestamp, ts);
    });

    test('toJson serializes all fields', () {
      final ping = buildPing();
      final json = ping.toJson();
      expect(json['vehicle_id'], 'v-001');
      expect(json['trip_id'], 'trip-abc');
      expect(json['latitude'], -23.5505);
      expect(json['longitude'], -46.6333);
      expect(json['accuracy'], 5.0);
      expect(json['speed'], 10.0);
      expect(json['heading'], 90.0);
      expect(json['timestamp'], ts.toIso8601String());
    });

    test('equality is based on props', () {
      final p1 = buildPing(timestamp: ts);
      final p2 = buildPing(timestamp: ts);
      expect(p1, equals(p2));
    });

    test('props differ when speed differs', () {
      final p1 = buildPing(speed: 10.0);
      final p2 = buildPing(speed: 20.0);
      expect(p1, isNot(equals(p2)));
    });
  });
}
