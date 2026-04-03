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
  final query = ref.watch(routesSearchQueryProvider).toLowerCase();

  return routesAsync.whenData((routes) {
    if (query.isEmpty) {
      return routes;
    }
    return routes.where((r) {
      return r.shortName.toLowerCase().contains(query) ||
          r.longName.toLowerCase().contains(query);
    }).toList();
  });
});
