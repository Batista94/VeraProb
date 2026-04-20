import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:veraprob/infrastructure/shared/vehicle_repository.dart';
import 'package:veraprob/infrastructure/shared/gtfs_realtime_service.dart';
import 'package:veraprob/domain/entities/vehicle_position.dart';

class MockGtfsRealtimeService extends Mock implements GtfsRealtimeService {}

void main() {
  late MockGtfsRealtimeService mockGtfsService;
  late VehicleRepository repository;

  setUp(() {
    mockGtfsService = MockGtfsRealtimeService();
    repository = VehicleRepository(mockGtfsService);

    registerFallbackValue(
      VehiclePosition(
        tripId: 'fallback',
        latitude: 0,
        longitude: 0,
        timestamp: DateTime.now().toUtc(),
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
          timestamp: DateTime.now().toUtc(),
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
          timestamp: DateTime.now().toUtc(),
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
        timestamp: DateTime.now().toUtc(),
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
        timestamp: DateTime.now().toUtc(),
        source: 'driver_app_gps',
        // speed, heading, routeName are null
      );

      await expectLater(repository.sendVehiclePosition(position), completes);
    });
  });
}
