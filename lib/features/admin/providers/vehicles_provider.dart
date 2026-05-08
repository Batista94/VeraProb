import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

final vehiclesListProvider = FutureProvider<List<Vehicle>>((ref) {
  final repository = ref.watch(vehicleAssetRepositoryProvider);
  return repository.getVehicles();
});

class _VehiclesSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final vehiclesSearchQueryProvider =
    NotifierProvider<_VehiclesSearchQueryNotifier, String>(
      _VehiclesSearchQueryNotifier.new,
    );

final filteredVehiclesProvider = Provider<AsyncValue<List<Vehicle>>>((ref) {
  final vehiclesAsync = ref.watch(vehiclesListProvider);
  final query = ref.watch(vehiclesSearchQueryProvider).toLowerCase();

  return switch (vehiclesAsync) {
    AsyncData(:final value) => AsyncData(
      query.isEmpty
          ? value
          : value.where((v) {
              return v.plate.toLowerCase().contains(query) ||
                  (v.model?.toLowerCase().contains(query) ?? false);
            }).toList(),
    ),
    AsyncError(:final error, :final stackTrace) => AsyncError(
      error,
      stackTrace,
    ),
    AsyncLoading() => const AsyncLoading(),
  };
});
