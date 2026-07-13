import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

final driversListProvider = FutureProvider<List<Driver>>((ref) async {
  final repository = ref.watch(driverRepositoryProvider);
  return repository.getDrivers();
});
