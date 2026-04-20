// Re-export all shared providers from state/providers/ so existing consumers
// of this file continue to work unchanged (C4 isolation — no infra/ imports).
export 'package:veraprob/state/providers/shared_providers.dart'
    show
        gtfsServiceProvider,
        vehicleRepositoryProvider,
        tripRepositoryProvider,
        sharedPreferencesProvider,
        currentDriverProvider,
        searchController,
        searchControllerProvider,
        searchQueryStreamProvider,
        vehiclePositionsStreamProvider;

export 'package:veraprob/state/providers/assets_providers.dart'
    show
        driverRepositoryProvider,
        vehicleAssetRepositoryProvider,
        transitRouteRepositoryProvider,
        driverListProvider;
