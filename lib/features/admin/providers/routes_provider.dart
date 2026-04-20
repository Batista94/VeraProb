import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

final routesListProvider = FutureProvider<List<TransitRoute>>((ref) {
  final repository = ref.watch(transitRouteRepositoryProvider);
  return repository.getRoutes();
});

final routesSearchQueryProvider = StateProvider<String>((ref) => '');

final filteredRoutesProvider = Provider<AsyncValue<List<TransitRoute>>>((ref) {
  final routesAsync = ref.watch(routesListProvider);
  final searchTerm = ref.watch(routesSearchQueryProvider).toLowerCase();

  return routesAsync.whenData((routes) {
    if (searchTerm.isEmpty) {
      return routes;
    }
    return routes.where((r) {
      return r.shortName.toLowerCase().contains(searchTerm) ||
          r.longName.toLowerCase().contains(searchTerm);
    }).toList();
  });
});
