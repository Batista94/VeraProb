import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:veraprob/features/shared/providers.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/domain/assets/i_driver_repository.dart';

class MockSharedPreferences extends Mock implements SharedPreferences {}

class FakeDriverRepository implements IDriverRepository {
  @override
  Future<int> batchUpsertFromCsv(
    String organizationId,
    List<Map<String, dynamic>> rows,
  ) async => rows.length;
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
  Future<void> archiveDriver(String id) async {}

  @override
  Future<void> updateDriver(Driver driver) async {}
}

void main() {
  group('Provider Definitions', () {
    late ProviderContainer container;
    late MockSharedPreferences mockPrefs;

    setUp(() {
      mockPrefs = MockSharedPreferences();

      when(() => mockPrefs.getStringList(any())).thenReturn([]);
      when(
        () => mockPrefs.setStringList(any(), any()),
      ).thenAnswer((_) async => true);
    });

    tearDown(() {
      container.dispose();
    });

    test('driverRepositoryProvider returns IDriverRepository', () {
      container = ProviderContainer.test(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          driverRepositoryProvider.overrideWithValue(FakeDriverRepository()),
        ],
      );

      final repo = container.read(driverRepositoryProvider);
      expect(repo, isA<IDriverRepository>());
    });

    test('driverListProvider returns Future<List<Driver>>', () async {
      container = ProviderContainer.test(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(mockPrefs),
          driverRepositoryProvider.overrideWithValue(FakeDriverRepository()),
        ],
      );

      final drivers = await container.read(driverListProvider.future);
      expect(drivers, isNotEmpty);
      expect(drivers.first.name, 'Test');
    });
  });
}
