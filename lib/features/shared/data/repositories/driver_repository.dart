import '../../domain/entities/driver.dart';

abstract class IDriverRepository {
  Future<List<Driver>> getDrivers();
  Future<void> addDriver(Driver driver);
  Future<void> deleteDriver(String id);
  Future<void> updateDriver(Driver driver);
}

class DriverRepositoryMock implements IDriverRepository {
  final List<Driver> _drivers = [
    const Driver(
      id: '1',
      name: 'João Silva',
      licenseNumber: '12345678900',
      status: DriverStatus.active,
    ),
    const Driver(
      id: '2',
      name: 'Maria Oliveira',
      licenseNumber: '98765432100',
      status: DriverStatus.active,
    ),
    const Driver(
      id: '3',
      name: 'Carlos Santos',
      licenseNumber: '11122233344',
      status: DriverStatus.inactive,
    ),
    const Driver(
      id: '4',
      name: 'Ana Pereira',
      licenseNumber: '55566677788',
      status: DriverStatus.active,
    ),
  ];

  @override
  Future<List<Driver>> getDrivers() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return List.from(_drivers);
  }

  @override
  Future<void> addDriver(Driver driver) async {
    await Future.delayed(const Duration(milliseconds: 800));
    // Check for duplicate CNH
    final exists = _drivers.any((d) => d.licenseNumber == driver.licenseNumber);
    if (exists) {
      throw Exception('DUPLICATE_CNH');
    }
    _drivers.add(driver);
  }

  @override
  Future<void> deleteDriver(String id) async {
    await Future.delayed(const Duration(milliseconds: 500));
    _drivers.removeWhere((d) => d.id == id);
  }

  @override
  Future<void> updateDriver(Driver driver) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final index = _drivers.indexWhere((d) => d.id == driver.id);
    if (index != -1) {
      _drivers[index] = driver;
    }
  }
}
