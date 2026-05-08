import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

final routesListProvider = FutureProvider<List<TransitRoute>>((ref) {
  final repository = ref.watch(transitRouteRepositoryProvider);
  return repository.getRoutes();
});

class _RoutesSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final routesSearchQueryProvider =
    NotifierProvider<_RoutesSearchQueryNotifier, String>(
      _RoutesSearchQueryNotifier.new,
    );

final filteredRoutesProvider = Provider<AsyncValue<List<TransitRoute>>>((ref) {
  final routesAsync = ref.watch(routesListProvider);
  final searchTerm = ref.watch(routesSearchQueryProvider).toLowerCase();

  return switch (routesAsync) {
    AsyncData(:final value) => AsyncData(
      searchTerm.isEmpty
          ? value
          : value.where((r) {
              return r.shortName.toLowerCase().contains(searchTerm) ||
                  r.longName.toLowerCase().contains(searchTerm);
            }).toList(),
    ),
    AsyncError(:final error, :final stackTrace) => AsyncError(
      error,
      stackTrace,
    ),
    AsyncLoading() => const AsyncLoading(),
  };
});
