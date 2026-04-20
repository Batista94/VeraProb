import 'package:flutter_test/flutter_test.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

void main() {
  group('VehiclePosition', () {
    final DateTime recentTs = DateTime.utc(2026, 4, 8, 12, 0, 0);
    final DateTime oldTs = recentTs.subtract(const Duration(minutes: 5));

    VehiclePosition buildPosition({
      String? id = 'pos-001',
      String tripId = 'trip-abc',
      double latitude = -23.5505,
      double longitude = -46.6333,
      double? speed = 40.0,
      double? heading = 90.0,
      DateTime? timestamp,
      String source = 'api_public',
      String? routeName = '809U',
      String? vehiclePlate = 'ABC-1234',
    }) => VehiclePosition(
      id: id,
      tripId: tripId,
      latitude: latitude,
      longitude: longitude,
      speed: speed,
      heading: heading,
      timestamp: timestamp ?? recentTs,
      source: source,
      routeName: routeName,
      vehiclePlate: vehiclePlate,
    );

    test('isStale returns false for recent position', () {
      final pos = buildPosition(timestamp: recentTs);
      expect(pos.isStale(nowUtc: recentTs), isFalse);
    });

    test('isStale returns true for position older than threshold', () {
      final pos = buildPosition(timestamp: oldTs);
      expect(pos.isStale(nowUtc: recentTs), isTrue);
    });

    test('isStale respects custom threshold', () {
      final pos = buildPosition(timestamp: oldTs);
      // 5 minutes old, threshold 10 minutes → not stale
      expect(
        pos.isStale(nowUtc: recentTs, threshold: const Duration(minutes: 10)),
        isFalse,
      );
      // 5 minutes old, threshold 2 minutes → stale
      expect(
        pos.isStale(nowUtc: recentTs, threshold: const Duration(minutes: 2)),
        isTrue,
      );
    });

    test('fromJson parses all fields', () {
      final ts = DateTime.utc(2026, 3, 25, 12, 0, 0);
      final json = {
        'id': 'pos-123',
        'trip_id': 'trip-xyz',
        'latitude': -23.5505,
        'longitude': -46.6333,
        'speed': 35.5,
        'heading': 180.0,
        'timestamp': ts.toIso8601String(),
        'source': 'driver_app_gps',
        'route_name': '875C',
        'vehicle_plate': 'DEF-5678',
      };
      final pos = VehiclePosition.fromJson(json);
      expect(pos.id, 'pos-123');
      expect(pos.tripId, 'trip-xyz');
      expect(pos.latitude, -23.5505);
      expect(pos.longitude, -46.6333);
      expect(pos.speed, 35.5);
      expect(pos.heading, 180.0);
      expect(pos.timestamp, ts);
      expect(pos.source, 'driver_app_gps');
      expect(pos.routeName, '875C');
      expect(pos.vehiclePlate, 'DEF-5678');
    });

    test('fromJson handles null optional fields', () {
      final json = {
        'trip_id': 'trip-null',
        'latitude': -23.0,
        'longitude': -46.0,
        'speed': null,
        'heading': null,
        'timestamp': recentTs.toIso8601String(),
        'source': 'api_public',
        'route_name': null,
        'vehicle_plate': null,
      };
      final pos = VehiclePosition.fromJson(json);
      expect(pos.id, isNull);
      expect(pos.speed, isNull);
      expect(pos.heading, isNull);
      expect(pos.routeName, isNull);
      expect(pos.vehiclePlate, isNull);
    });

    test('toJson serializes required fields', () {
      final ts = DateTime.utc(2026, 1, 1);
      final pos = buildPosition(
        tripId: 'trip-abc',
        latitude: -23.5505,
        longitude: -46.6333,
        speed: 40.0,
        heading: 90.0,
        timestamp: ts,
        source: 'api_public',
      );
      final json = pos.toJson();
      expect(json['trip_id'], 'trip-abc');
      expect(json['latitude'], -23.5505);
      expect(json['longitude'], -46.6333);
      expect(json['speed'], 40.0);
      expect(json['heading'], 90.0);
      expect(json['timestamp'], ts.toIso8601String());
      expect(json['source'], 'api_public');
    });

    test('equality is based on props', () {
      final p1 = buildPosition(timestamp: recentTs);
      final p2 = buildPosition(timestamp: recentTs);
      expect(p1, equals(p2));
    });

    test('props differ when latitude differs', () {
      final p1 = buildPosition(latitude: -23.0);
      final p2 = buildPosition(latitude: -24.0);
      expect(p1, isNot(equals(p2)));
    });
  });
}
