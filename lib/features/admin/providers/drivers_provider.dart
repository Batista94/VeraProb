import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers.dart';
import '../../driver/domain/entities/driver.dart';

// Provider to fetch the list of drivers
final driversListProvider = FutureProvider<List<Driver>>((ref) async {
  final repository = ref.watch(driverRepositoryProvider);
  return repository.getDrivers();
});
