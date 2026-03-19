import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:veraprob/features/shared/providers.dart';

import 'package:veraprob/features/shared/data/repositories/vehicle_repository.dart';
import 'package:veraprob/features/shared/domain/entities/driver.dart';
import 'package:veraprob/features/shared/data/repositories/driver_repository.dart';
import 'package:veraprob/features/shared/data/repositories/trip_repository.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

class MockVehiclePositionService extends Mock
    implements IVehiclePositionService {}

class MockTripRepository extends Mock implements ITripRepository {}

class FakeDriverRepository implements IDriverRepository {
  @override
  Future<List<Driver>> getDrivers() async => [
    const Driver(
      id: '1',
      organizationId: 'test-org',
      name: 'Test',
      licenseNumber: '111',
      status: DriverStatus.active,
    ),
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
    late MockVehiclePositionService mockVehicleRepo;

    setUp(() {
      mockPrefs = MockSharedPreferences();
      mockVehicleRepo = MockVehiclePositionService();

      when(() => mockPrefs.getStringList(any())).thenReturn([]);
      when(
        () => mockPrefs.setStringList(any(), any()),
      ).thenAnswer((_) async => true);
    });

    tearDown(() {
      container.dispose();
    });

    test('driverRepositoryProvider returns IDriverRepository', () {
      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          driverRepositoryProvider.overrideWithValue(FakeDriverRepository()),
        ],
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

      const testDriver = Driver(
        id: '1',
        organizationId: 'test-org',
        name: 'Test',
        licenseNumber: '111',
        status: DriverStatus.active,
      );
      container.read(currentDriverProvider.notifier).state = testDriver;
      expect(container.read(currentDriverProvider), testDriver);
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
