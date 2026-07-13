import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

final routesListProvider = FutureProvider<List<TransitRoute>>((ref) {
  final repository = ref.watch(transitRouteRepositoryProvider);
  return repository.getRoutes();
});
