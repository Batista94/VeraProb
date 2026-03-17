import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers.dart';
import '../../../domain/entities/vehicle.dart';

final vehiclesListProvider = FutureProvider<List<Vehicle>>((ref) {
  final repository = ref.watch(vehicleAssetRepositoryProvider);
  return repository.getVehicles();
});

final vehiclesSearchQueryProvider = StateProvider<String>((ref) => '');

final filteredVehiclesProvider = Provider<AsyncValue<List<Vehicle>>>((ref) {
  final vehiclesAsync = ref.watch(vehiclesListProvider);
  final query = ref.watch(vehiclesSearchQueryProvider).toLowerCase();

  return vehiclesAsync.whenData((vehicles) {
    if (query.isEmpty) return vehicles;
    return vehicles.where((v) {
      return v.plate.toLowerCase().contains(query) ||
          (v.model?.toLowerCase().contains(query) ?? false);
    }).toList();
  });
});
