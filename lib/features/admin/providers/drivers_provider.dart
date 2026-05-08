import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/features/shared/providers.dart';
import 'package:veraprob/application/shared/app_types.dart';

// Provider to fetch the list of drivers
final driversListProvider = FutureProvider<List<Driver>>((ref) async {
  final repository = ref.watch(driverRepositoryProvider);
  return repository.getDrivers();
});

// Search searchTerm provider
class _DriversSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final driversSearchQueryProvider =
    NotifierProvider<_DriversSearchQueryNotifier, String>(
      _DriversSearchQueryNotifier.new,
    );

// Toggle: show archived (inactive + archived_at_utc != null) drivers.
// Default false — supervisors must opt-in to view historical records.
class _ShowArchivedDriversNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
  void toggle() => state = !state;
}

final showArchivedDriversProvider =
    NotifierProvider<_ShowArchivedDriversNotifier, bool>(
      _ShowArchivedDriversNotifier.new,
    );

// Filtered drivers provider
// INV-3: archived drivers kept in DB; hidden by default, not deleted.
final filteredDriversProvider = Provider<AsyncValue<List<Driver>>>((ref) {
  final driversAsync = ref.watch(driversListProvider);
  final searchTerm = ref.watch(driversSearchQueryProvider).toLowerCase();
  final showArchived = ref.watch(showArchivedDriversProvider);

  return switch (driversAsync) {
    AsyncData(:final value) => AsyncData(() {
      var result = value.where((d) {
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
    }()),
    AsyncError(:final error, :final stackTrace) => AsyncError(
      error,
      stackTrace,
    ),
    AsyncLoading() => const AsyncLoading(),
  };
});
