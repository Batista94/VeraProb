import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:busflow/features/shared/providers.dart';

import 'package:busflow/features/shared/data/repositories/vehicle_repository.dart';
import 'package:busflow/features/driver/domain/entities/driver.dart';
import 'package:busflow/features/driver/data/repositories/driver_repository.dart';
import 'package:busflow/features/stops/domain/entities/bus_stop.dart';
import 'package:busflow/core/geolocation/geo_locator.dart';
import 'package:busflow/features/driver/presentation/tracking_service.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockGeoLocatorService extends Mock implements GeoLocatorService {}

class MockVehiclePositionService extends Mock
    implements IVehiclePositionService {}

class FakeDriverRepository implements IDriverRepository {
  @override
  Future<List<Driver>> getDrivers() async => [
    const Driver(id: '1', name: 'Test', licenseNumber: '111'),
  ];

  @override
  Future<void> addDriver(Driver driver) async {}

  @override
  Future<void> deleteDriver(String id) async {}

  @override
  Future<void> updateDriver(Driver driver) async {}
}

void main() {
  group('Provider Definitions', () {
    late ProviderContainer container;
    late MockSharedPreferences mockPrefs;
    late MockGeoLocatorService mockGeoLocator;
    late MockVehiclePositionService mockVehicleRepo;

    setUp(() {
      mockPrefs = MockSharedPreferences();
      mockGeoLocator = MockGeoLocatorService();
      mockVehicleRepo = MockVehiclePositionService();

      when(() => mockPrefs.getStringList(any())).thenReturn([]);
      when(
        () => mockPrefs.setStringList(any(), any()),
      ).thenAnswer((_) async => true);
    });

    tearDown(() {
      container.dispose();
    });

    test('favoritesProvider initializes with empty list', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      final favorites = container.read(favoritesProvider);
      expect(favorites, isEmpty);
    });

    test('favoritesProvider adds and removes favorites', () async {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      await container.read(favoritesProvider.notifier).toggleFavorite('TripA');
      expect(container.read(favoritesProvider), contains('TripA'));

      await container.read(favoritesProvider.notifier).toggleFavorite('TripA');
      expect(container.read(favoritesProvider), isEmpty);
    });

    test('driverRepositoryProvider returns IDriverRepository', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      final repo = container.read(driverRepositoryProvider);
      expect(repo, isA<IDriverRepository>());
    });

    test('driverListProvider returns Future<List<Driver>>', () async {
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          driverRepositoryProvider.overrideWithValue(FakeDriverRepository()),
        ],
      );

      final drivers = await container.read(driverListProvider.future);
      expect(drivers, isNotEmpty);
      expect(drivers.first.name, 'Test');
    });

    test('currentDriverProvider starts as null', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      final driver = container.read(currentDriverProvider);
      expect(driver, isNull);
    });

    test('currentDriverProvider stores a Driver', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      const testDriver = Driver(id: '1', name: 'Test', licenseNumber: '111');
      container.read(currentDriverProvider.notifier).state = testDriver;
      expect(container.read(currentDriverProvider), testDriver);
    });

    test('trackingServiceProvider returns TrackingService', () {
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          geoLocatorProvider.overrideWithValue(mockGeoLocator),
          vehicleRepositoryProvider.overrideWithValue(mockVehicleRepo),
        ],
      );

      final service = container.read(trackingServiceProvider);
      expect(service, isA<TrackingService>());
    });

    test('searchControllerProvider returns broadcast StreamController', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      final ctrl = container.read(searchControllerProvider);
      expect(ctrl, isA<StreamController<String>>());
    });

    test('searchQueryStreamProvider emits empty string initially', () async {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      // Read the provider to trigger subscription
      final sub = container.listen(searchQueryStreamProvider, (_, _) {});
      await Future.delayed(const Duration(milliseconds: 50));
      final value = container.read(searchQueryStreamProvider);
      expect(value.value, '');
      sub.close();
    });

    test('showFavoritesProvider starts as false', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      expect(container.read(showFavoritesProvider), false);
    });

    test('showFavoritesProvider can be toggled', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      container.read(showFavoritesProvider.notifier).state = true;
      expect(container.read(showFavoritesProvider), true);
    });

    test('busStopRepositoryProvider returns a BusStopRepository', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      final repo = container.read(busStopRepositoryProvider);
      expect(repo, isNotNull);
    });

    test('busStopsFutureProvider returns a list of BusStops', () async {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      final stops = await container.read(busStopsFutureProvider.future);
      expect(stops, isA<List<BusStop>>());
      expect(stops, isNotEmpty);
    });

    test('vehiclePositionsStreamProvider returns a Stream', () {
      when(
        () => mockVehicleRepo.getVehiclePositions(),
      ).thenAnswer((_) => Stream.value([]));

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          vehicleRepositoryProvider.overrideWithValue(mockVehicleRepo),
        ],
      );

      // Just verifying the provider can be read without errors
      final asyncValue = container.read(vehiclePositionsStreamProvider);
      expect(asyncValue, isNotNull);
    });

    test('gtfsServiceProvider returns GtfsRealtimeService', () {
      container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(mockPrefs)],
      );

      final service = container.read(gtfsServiceProvider);
      expect(service, isNotNull);
    });
  });
}
