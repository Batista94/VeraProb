import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/infrastructure/shared/vehicle_repository.dart';
import 'package:veraprob/infrastructure/shared/gtfs_realtime_service.dart';
import 'package:veraprob/application/shared/vehicle_position_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veraprob/application/shared/app_types.dart';
import 'package:veraprob/infrastructure/shared/trip_repository_impl.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';
export 'package:veraprob/state/providers/assets_providers.dart'
    show
        driverRepositoryProvider,
        vehicleAssetRepositoryProvider,
        transitRouteRepositoryProvider,
        driverListProvider;

// Services
final gtfsServiceProvider = Provider((ref) => GtfsRealtimeService());

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

// Repositories
final vehicleRepositoryProvider = Provider<IVehiclePositionService>((ref) {
  final gtfsService = ref.read(gtfsServiceProvider);
  return VehicleRepository(gtfsService);
});

final currentDriverProvider = StateProvider<Driver?>((ref) => null);

// View Models / Streams

// Global Broadcast Controller for Search (Simple MVP Pattern)
final searchController = StreamController<String>.broadcast();
final searchControllerProvider = Provider((ref) => searchController);

final searchQueryStreamProvider = StreamProvider<String>((ref) async* {
  yield ''; // Start with empty
  yield* searchController.stream;
});

final tripRepositoryProvider = Provider<ITripRepository>((ref) {
  return TripRepositoryImpl(ref.watch(supabaseClientProvider));
});

final vehiclePositionsStreamProvider =
    StreamProvider<List<VehiclePositionView>>((ref) {
      final repository = ref.read(vehicleRepositoryProvider);
      final allPositions = repository.getVehiclePositions();

      // Watch filters
      final queryAsync = ref.watch(searchQueryStreamProvider);
      final query = queryAsync.value?.toLowerCase() ?? '';

      return allPositions.map((positions) {
        var filtered = positions;

        // Filter by Search Query
        if (query.isNotEmpty) {
          filtered = filtered.where((pos) {
            final matchTripId = pos.tripId.toLowerCase().contains(query);
            final matchRoute =
                pos.routeName?.toLowerCase().contains(query) ?? false;
            return matchTripId || matchRoute;
          }).toList();
        }

        // Map to View Model
        return filtered.map(VehiclePositionView.fromDomain).toList();
      });
    });
