import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

final vehiclesListProvider = FutureProvider<List<Vehicle>>((ref) {
  final repository = ref.watch(vehicleAssetRepositoryProvider);
  return repository.getVehicles();
});
