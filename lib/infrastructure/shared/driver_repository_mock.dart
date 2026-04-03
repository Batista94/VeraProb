import 'package:veraprob/domain/assets/i_driver_repository.dart';
import 'package:veraprob/domain/entities/driver.dart';

class DriverRepositoryMock implements IDriverRepository {
  static const _devOrgId = 'dev-org-mock';

  final List<Driver> _drivers = [
    const Driver(
      id: '1',
      organizationId: _devOrgId,
      name: 'João Silva',
      licenseNumber: '12345678900',
      status: DriverStatus.active,
    ),
    const Driver(
      id: '2',
      organizationId: _devOrgId,
      name: 'Maria Oliveira',
      licenseNumber: '98765432100',
      status: DriverStatus.active,
    ),
    const Driver(
      id: '3',
      organizationId: _devOrgId,
      name: 'Carlos Santos',
      licenseNumber: '11122233344',
      status: DriverStatus.inactive,
    ),
    const Driver(
      id: '4',
      organizationId: _devOrgId,
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
