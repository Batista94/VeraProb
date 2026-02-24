import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:busflow/features/driver/presentation/tracking_service.dart';
import 'package:busflow/core/geolocation/geo_locator.dart';
import 'package:busflow/features/shared/data/repositories/vehicle_repository.dart';
import 'package:busflow/features/shared/data/repositories/trip_repository.dart';
import 'package:busflow/features/shared/domain/entities/vehicle_position.dart';
import 'package:busflow/features/shared/domain/entities/trip.dart';
import 'package:geolocator/geolocator.dart';

class MockGeoLocatorService extends Mock implements GeoLocatorService {}

class MockVehiclePositionService extends Mock
    implements IVehiclePositionService {}

class MockTripRepository extends Mock implements ITripRepository {}

class FakeVehiclePosition extends Fake implements VehiclePosition {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeVehiclePosition());
  });

  late TrackingService service;
  late MockGeoLocatorService mockGeoLocator;
  late MockVehiclePositionService mockVehicleRepository;
  late MockTripRepository mockTripRepository;

  setUp(() {
    mockGeoLocator = MockGeoLocatorService();
    mockVehicleRepository = MockVehiclePositionService();
    mockTripRepository = MockTripRepository();
    service = TrackingService(
      mockGeoLocator,
      mockVehicleRepository,
      mockTripRepository,
    );

    // Default stubbing
    when(
      () => mockVehicleRepository.sendVehiclePosition(any()),
    ).thenAnswer((_) async {});
    when(() => mockTripRepository.startTrip(any(), any())).thenAnswer(
      (_) async => Trip(
        id: 'trip_123',
        driverId: 'driver_1',
        routeId: 'route_1',
        startTime: DateTime.now(),
      ),
    );
    when(() => mockTripRepository.endTrip(any())).thenAnswer((_) async {});
  });

  final mockPosition = Position(
    longitude: -46.63,
    latitude: -23.55,
    timestamp: DateTime.now(),
    accuracy: 10,
    altitude: 0,
    heading: 90,
    speed: 15,
    speedAccuracy: 0,
    altitudeAccuracy: 0,
    headingAccuracy: 0,
  );

  test('startTracking initializes subscription and calls startTrip', () async {
    when(
      () => mockGeoLocator.getPositionStream(),
    ).thenAnswer((_) => Stream.value(mockPosition));

    await service.startTracking('route_1', 'driver_1');

    verify(() => mockTripRepository.startTrip('driver_1', 'route_1')).called(1);
    expect(service.currentTripDbId, 'trip_123');

    // Allow stream to process
    await Future.delayed(Duration.zero);

    final captured = verify(
      () => mockVehicleRepository.sendVehiclePosition(captureAny()),
    ).captured;
    expect(captured, hasLength(1));
    final pos = captured.first as VehiclePosition;
    expect(pos.tripId, 'route_1'); // UI expects routeId as tripId for display
    expect(pos.source, 'driver_app_gps');
  });

  test('stopTracking cancels subscription and calls endTrip', () async {
    when(
      () => mockGeoLocator.getPositionStream(),
    ).thenAnswer((_) => Stream.value(mockPosition));

    await service.startTracking('route_1', 'driver_1');
    await service.stopTracking();

    verify(() => mockTripRepository.endTrip('trip_123')).called(1);
    expect(service.currentTripDbId, isNull);
  });
}
