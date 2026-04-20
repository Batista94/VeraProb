import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:veraprob/domain/assets/i_transit_route_repository.dart';
import 'package:veraprob/domain/assets/i_vehicle_asset_repository.dart';
import 'package:veraprob/domain/assets/i_driver_repository.dart';
import 'package:veraprob/domain/entities/driver.dart';
import 'package:veraprob/infrastructure/assets/postgres_transit_route_repository.dart';
import 'package:veraprob/infrastructure/assets/postgres_vehicle_asset_repository.dart';
import 'package:veraprob/infrastructure/assets/postgres_driver_repository.dart';
import 'package:veraprob/infrastructure/providers/supabase_provider.dart';

/// Canonical provider for [ITransitRouteRepository].
final transitRouteRepositoryProvider = Provider<ITransitRouteRepository>((ref) {
  return PostgresTransitRouteRepository(ref.watch(supabaseClientProvider));
});

/// Canonical provider for [IVehicleAssetRepository].
final vehicleAssetRepositoryProvider = Provider<IVehicleAssetRepository>((ref) {
  return PostgresVehicleAssetRepository(ref.watch(supabaseClientProvider));
});

/// Canonical provider for [IDriverRepository].
final driverRepositoryProvider = Provider<IDriverRepository>((ref) {
  return PostgresDriverRepository(ref.watch(supabaseClientProvider));
});

/// Cached driver list — invalidate after add/update/delete operations.
final driverListProvider = FutureProvider<List<Driver>>((ref) {
  return ref.read(driverRepositoryProvider).getDrivers();
});
