import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/application/shared/vehicle_position_view.dart';
import 'package:veraprob/infrastructure/shared/gtfs_realtime_service.dart';
import 'package:veraprob/infrastructure/shared/trip_repository_impl.dart';
import 'package:veraprob/infrastructure/shared/vehicle_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
import 'package:veraprob/core/utils/date_time_provider.dart';
import 'package:veraprob/infrastructure/shared/evidence_url_service.dart';

final evidenceUrlServiceProvider = Provider<EvidenceUrlService>((ref) {
  return const EvidenceUrlService();
});

// ── Transport / GTFS ─────────────────────────────────────────────────────────

// ── Time ──────────────────────────────────────────────────────────────────────
// Deterministic time provider — injects IDateTimeProvider for testability.
final dateTimeProviderProvider = Provider<IDateTimeProvider>(
  (ref) => BrazilDateTimeProvider(),
);

final gtfsServiceProvider = Provider(
  (ref) => GtfsRealtimeService(ref.watch(dateTimeProviderProvider)),
);

final vehicleRepositoryProvider = Provider<IVehiclePositionService>((ref) {
  final gtfsService = ref.read(gtfsServiceProvider);
  return VehicleRepository(gtfsService);
});

final tripRepositoryProvider = Provider<ITripRepository>((ref) {
  return TripRepositoryImpl(
    ref.watch(supabaseClientProvider),
    ref.watch(dateTimeProviderProvider),
  );
});

// ── SharedPreferences stub ───────────────────────────────────────────────────

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

// ── Driver state ─────────────────────────────────────────────────────────────

class _CurrentDriverNotifier extends Notifier<Driver?> {
  @override
  Driver? build() => null;

  void set(Driver? value) => state = value;
}

final currentDriverProvider = NotifierProvider<_CurrentDriverNotifier, Driver?>(
  _CurrentDriverNotifier.new,
);

// ── Search stream ─────────────────────────────────────────────────────────────

// Global Broadcast Controller for Search (Simple MVP Pattern)
final searchController = StreamController<String>.broadcast();
final searchControllerProvider = Provider((ref) => searchController);

final searchQueryStreamProvider = StreamProvider<String>((ref) async* {
  yield '';
  yield* searchController.stream;
});

// ── Vehicle positions ─────────────────────────────────────────────────────────

final vehiclePositionsStreamProvider =
    StreamProvider<List<VehiclePositionView>>((ref) {
      final repository = ref.read(vehicleRepositoryProvider);
      final allPositions = repository.getVehiclePositions();

      final queryAsync = ref.watch(searchQueryStreamProvider);
      final query = queryAsync.value?.toLowerCase() ?? '';

      return allPositions.map((positions) {
        var filtered = positions;

        if (query.isNotEmpty) {
          filtered = filtered.where((pos) {
            final matchTripId = pos.tripId.toLowerCase().contains(query);
            final matchRoute =
                pos.routeName?.toLowerCase().contains(query) ?? false;
            return matchTripId || matchRoute;
          }).toList();
        }

        return filtered.map(VehiclePositionView.fromDomain).toList();
      });
    });
