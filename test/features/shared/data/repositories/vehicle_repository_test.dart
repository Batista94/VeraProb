import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:veraprob/features/shared/data/repositories/vehicle_repository.dart';
import 'package:veraprob/features/shared/data/services/gtfs_realtime_service.dart';
import 'package:veraprob/features/shared/domain/entities/vehicle_position.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGtfsRealtimeService extends Mock implements GtfsRealtimeService {}

void main() {
  late MockSupabaseClient mockSupabase;
  late MockGtfsRealtimeService mockGtfsService;
  late VehicleRepository repository;

  setUp(() {
    mockSupabase = MockSupabaseClient();
    mockGtfsService = MockGtfsRealtimeService();
    repository = VehicleRepository(mockSupabase, mockGtfsService);

    registerFallbackValue(
      VehiclePosition(
        tripId: 'fallback',
        latitude: 0,
        longitude: 0,
        timestamp: DateTime.now(),
        source: 'test',
      ),
    );
  });

  group('VehicleRepository', () {
    test('getVehiclePositions returns stream from gtfsService', () {
      final mockPositions = [
        VehiclePosition(
          tripId: 'trip_001',
          latitude: -23.55,
          longitude: -46.63,
          timestamp: DateTime.now(),
          source: 'api_public',
          routeName: '809U',
        ),
      ];

      when(
        () => mockGtfsService.getVehiclePositions(),
      ).thenAnswer((_) => Stream.value(mockPositions));

      final stream = repository.getVehiclePositions();
      expect(stream, isA<Stream<List<VehiclePosition>>>());
    });

    test('getVehiclePositions caches positions by tripId', () async {
      final mockPositions = [
        VehiclePosition(
          tripId: 'trip_001',
          latitude: -23.55,
          longitude: -46.63,
          timestamp: DateTime.now(),
          source: 'api_public',
        ),
      ];

      when(
        () => mockGtfsService.getVehiclePositions(),
      ).thenAnswer((_) => Stream.value(mockPositions));

      final positions = await repository.getVehiclePositions().first;
      expect(positions.length, 1);
      expect(positions.first.tripId, 'trip_001');
    });

    test('sendVehiclePosition completes without throwing', () async {
      final position = VehiclePosition(
        tripId: 'trip_send',
        latitude: -23.55,
        longitude: -46.63,
        timestamp: DateTime.now(),
        source: 'driver_app_gps',
        speed: 15.0,
        heading: 90.0,
        routeName: '809U',
      );

      // sendVehiclePosition only prints (Supabase insert is commented out)
      await expectLater(repository.sendVehiclePosition(position), completes);
    });

    test('sendVehiclePosition handles null optional fields', () async {
      final position = VehiclePosition(
        tripId: 'trip_nulls',
        latitude: -23.55,
        longitude: -46.63,
        timestamp: DateTime.now(),
        source: 'driver_app_gps',
        // speed, heading, routeName are null
      );

      await expectLater(repository.sendVehiclePosition(position), completes);
    });
  });
}
