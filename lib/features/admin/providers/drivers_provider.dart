import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

// Provider to fetch the list of drivers
final driversListProvider = FutureProvider<List<Driver>>((ref) async {
  final repository = ref.watch(driverRepositoryProvider);
  return repository.getDrivers();
});

// Search searchTerm provider
final driversSearchQueryProvider = StateProvider<String>((ref) => '');

// Toggle: show archived (inactive + archived_at_utc != null) drivers.
// Default false — supervisors must opt-in to view historical records.
final showArchivedDriversProvider = StateProvider<bool>((ref) => false);

// Filtered drivers provider
// INV-3: archived drivers kept in DB; hidden by default, not deleted.
final filteredDriversProvider = Provider<AsyncValue<List<Driver>>>((ref) {
  final driversAsync = ref.watch(driversListProvider);
  final searchTerm = ref.watch(driversSearchQueryProvider).toLowerCase();
  final showArchived = ref.watch(showArchivedDriversProvider);

  return driversAsync.whenData((drivers) {
    var result = drivers.where((d) {
      if (!showArchived && d.isArchived) return false;
      return true;
    });

    if (searchTerm.isNotEmpty) {
      result = result.where((d) {
        return d.name.toLowerCase().contains(searchTerm) ||
            d.licenseNumber.contains(searchTerm);
      });
    }

    return result.toList();
  });
});
