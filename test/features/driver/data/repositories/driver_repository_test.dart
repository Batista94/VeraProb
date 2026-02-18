import 'package:flutter_test/flutter_test.dart';
import 'package:busflow/features/driver/data/repositories/driver_repository.dart';
import 'package:busflow/features/driver/domain/entities/driver.dart';

void main() {
  group('DriverRepositoryMock', () {
    late DriverRepositoryMock repository;

    setUp(() {
      repository = DriverRepositoryMock();
    });

    test('getDrivers should return a non-empty list', () async {
      final drivers = await repository.getDrivers();
      expect(drivers, isNotEmpty);
    });

    test('getDrivers should return exactly 4 mock drivers', () async {
      final drivers = await repository.getDrivers();
      expect(drivers.length, 4);
    });

    test('getDrivers should return list of Driver instances', () async {
      final drivers = await repository.getDrivers();
      expect(drivers, everyElement(isA<Driver>()));
    });

    test('first driver should be João Silva', () async {
      final drivers = await repository.getDrivers();
      expect(drivers.first.name, 'João Silva');
      expect(drivers.first.id, '1');
    });

    test('all drivers should have non-empty license numbers', () async {
      final drivers = await repository.getDrivers();
      for (final driver in drivers) {
        expect(driver.licenseNumber, isNotEmpty);
      }
    });

    test('all driver ids should be unique', () async {
      final drivers = await repository.getDrivers();
      final ids = drivers.map((d) => d.id).toSet();
      expect(ids.length, drivers.length);
    });
  });
}
