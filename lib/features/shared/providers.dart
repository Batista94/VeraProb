import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/supabase_client.dart';
import '../../core/geolocation/geo_locator.dart';
import 'package:geolocator/geolocator.dart'; // Import Position type
import '../driver/presentation/tracking_service.dart';
import 'data/repositories/vehicle_repository.dart';
import 'data/services/gtfs_realtime_service.dart';
import 'domain/entities/vehicle_position.dart';
import '../stops/data/repositories/bus_stop_repository.dart';
import '../stops/domain/entities/bus_stop.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'data/repositories/favorites_repository.dart';
import '../driver/data/repositories/driver_repository.dart';
import '../driver/domain/entities/driver.dart';
import '../driver/data/repositories/driver_repository_impl.dart';
import 'data/repositories/trip_repository.dart';
import 'data/repositories/trip_repository_impl.dart';
// Services

final gtfsServiceProvider = Provider((ref) => GtfsRealtimeService());

final geoLocatorProvider = Provider((ref) => GeoLocatorService());

final userLocationStreamProvider = StreamProvider<Position>((ref) {
  final geoLocator = ref.read(geoLocatorProvider);
  return geoLocator.getPositionStream();
});

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(),
);

// Repositories
final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, List<String>>((ref) {
      final prefs = ref.read(sharedPreferencesProvider);
      return FavoritesNotifier(prefs);
    });

final vehicleRepositoryProvider = Provider<IVehiclePositionService>((ref) {
  final gtfsService = ref.read(gtfsServiceProvider);
  // Using the global supabase client from config
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

// Features
final trackingServiceProvider = Provider((ref) {
  final geoLocator = ref.read(geoLocatorProvider);
  final repository = ref.read(vehicleRepositoryProvider);
  final tripRepository = ref.read(tripRepositoryProvider);
  return TrackingService(geoLocator, repository, tripRepository);
});

// View Models / Streams
// View Models / Streams

// Global Broadcast Controller for Search (Simple MVP Pattern)
// We use a global controller here to avoid complex lifecycle management in this MVP
// Global Broadcast Controller for Search (Simple MVP Pattern)
final searchController = StreamController<String>.broadcast();
final searchControllerProvider = Provider((ref) => searchController);

final searchQueryStreamProvider = StreamProvider<String>((ref) async* {
  yield ''; // Start with empty
  yield* searchController.stream;
});

final showFavoritesProvider = StateProvider<bool>((ref) => false);

final tripRepositoryProvider = Provider<ITripRepository>((ref) {
  return TripRepositoryImpl(supabase);
});

final vehiclePositionsStreamProvider = StreamProvider<List<VehiclePosition>>((
  ref,
) {
  final repository = ref.read(vehicleRepositoryProvider);
  final allPositions = repository.getVehiclePositions();

  // Watch filters
  final queryAsync = ref.watch(searchQueryStreamProvider);
  final query = queryAsync.value?.toLowerCase() ?? '';

  final showFavorites = ref.watch(showFavoritesProvider);
  final favorites = ref.watch(favoritesProvider);

  return allPositions.map((positions) {
    var filtered = positions;

    // Filter by Favorites
    if (showFavorites) {
      filtered = filtered
          .where((pos) => favorites.contains(pos.tripId))
          .toList();
    }

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

final busStopRepositoryProvider = Provider((ref) => BusStopRepository());

final busStopsFutureProvider = FutureProvider<List<BusStop>>((ref) {
  final repository = ref.read(busStopRepositoryProvider);
  return repository.getNearbyStops(-23.5505, -46.6333);
});
