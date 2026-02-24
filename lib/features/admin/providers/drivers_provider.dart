import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers.dart';
import '../../driver/domain/entities/driver.dart';

// Provider to fetch the list of drivers
final driversListProvider = FutureProvider<List<Driver>>((ref) async {
  final repository = ref.watch(driverRepositoryProvider);
  return repository.getDrivers();
});

// Search query provider
final driversSearchQueryProvider = StateProvider<String>((ref) => '');

// Filtered drivers provider
final filteredDriversProvider = Provider<AsyncValue<List<Driver>>>((ref) {
  final driversAsync = ref.watch(driversListProvider);
  final query = ref.watch(driversSearchQueryProvider).toLowerCase();

  return driversAsync.whenData((drivers) {
    if (query.isEmpty) return drivers;
    return drivers.where((d) {
      return d.name.toLowerCase().contains(query) ||
          d.licenseNumber.contains(query);
    }).toList();
  });
});
