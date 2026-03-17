import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_client.dart';
import 'data/repositories/vehicle_repository.dart';
import 'data/services/gtfs_realtime_service.dart';
import 'domain/entities/vehicle_position.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/repositories/driver_repository.dart';
import 'domain/entities/driver.dart';
import 'data/repositories/driver_repository_impl.dart';
import 'data/repositories/trip_repository.dart';
import 'data/repositories/trip_repository_impl.dart';
import '../assets/data/repositories/vehicle_asset_repository.dart';
import '../assets/data/repositories/vehicle_asset_repository_impl.dart';
import '../assets/data/repositories/transit_route_repository.dart';
import '../assets/data/repositories/transit_route_repository_impl.dart';

// Services
final gtfsServiceProvider = Provider((ref) => GtfsRealtimeService());

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

// Repositories
final vehicleRepositoryProvider = Provider<IVehiclePositionService>((ref) {
  final gtfsService = ref.read(gtfsServiceProvider);
  return VehicleRepository(supabase, gtfsService);
});

final driverRepositoryProvider = Provider<IDriverRepository>(
  (ref) => DriverRepositoryImpl(supabase),
);

final driverListProvider = FutureProvider<List<Driver>>((ref) {
  final repository = ref.read(driverRepositoryProvider);
  return repository.getDrivers();
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
  return TripRepositoryImpl(supabase);
});

final vehicleAssetRepositoryProvider = Provider<IVehicleAssetRepository>((ref) {
  return VehicleAssetRepositoryImpl(supabase);
});

final transitRouteRepositoryProvider = Provider<ITransitRouteRepository>((ref) {
  return TransitRouteRepositoryImpl(supabase);
});

final vehiclePositionsStreamProvider = StreamProvider<List<VehiclePosition>>((
  ref,
) {
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

    return filtered;
  });
});
