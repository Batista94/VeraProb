import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart'; // Import Position

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/domain/entities/vehicle_position.dart';

import '../../shared/providers.dart';
import 'widgets/bus_detail_sheet.dart';
import '../../../../core/services/notification_service.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  List<LatLng> _selectedRoutePoints = [];
  String? _trackedBusId; // Bus tracked for proximity alert
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _notificationService.initialize();
  }

  void _checkProximity(List<VehiclePosition> positions, Position? userPos) {
    if (_trackedBusId == null || userPos == null) return;

    final trackedBus = positions.firstWhere(
      (p) => p.tripId == _trackedBusId,
      orElse: () => positions.first, // Fallback (or handle not found)
    );

    // Check if actsually found (by comparing ID or if list was empty/single)
    if (trackedBus.tripId != _trackedBusId) return;

    final distance = const Distance().as(
      LengthUnit.Meter,
      LatLng(userPos.latitude, userPos.longitude),
      LatLng(trackedBus.latitude, trackedBus.longitude),
    );

    if (distance < 1000) {
      // 1km threshold
      _notificationService.showNotification(
        'O ônibus está chegando! 🚌',
        'O veículo da linha ${trackedBus.routeName ?? "selecionada"} está a ${distance.toInt()}m de você.',
      );
      // Clear tracking to avoid spam
      setState(() {
        _trackedBusId = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alerta de proximidade disparado! 🔔')),
        );
      }
    }
  }

  void _showRoutePolyline(VehiclePosition pos) {
    // Mock polyline: 5 points around the bus/route
    // In a real app, we would fetch shapes.txt from GTFS
    final center = LatLng(pos.latitude, pos.longitude);
    setState(() {
      _selectedRoutePoints = [
        LatLng(center.latitude - 0.005, center.longitude - 0.005),
        LatLng(center.latitude - 0.002, center.longitude - 0.002),
        center,
        LatLng(center.latitude + 0.002, center.longitude + 0.002),
        LatLng(center.latitude + 0.005, center.longitude + 0.005),
      ];
    });
  }

  void _clearRoutePolyline() {
    setState(() {
      _selectedRoutePoints = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final vehiclePositionsAsync = ref.watch(vehiclePositionsStreamProvider);
    final userLocationAsync = ref.watch(userLocationStreamProvider);

    // Proximity check side-effect
    ref.listen(vehiclePositionsStreamProvider, (previous, next) {
      if (next.hasValue && _trackedBusId != null) {
        userLocationAsync.whenData((userPos) {
          _checkProximity(next.value!, userPos);
        });
      }
    });

    final busStopsAsync = ref.watch(busStopsFutureProvider);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(-23.550520, -46.633308), // São Paulo
              initialZoom: 15.0,
              onTap: (_, _) => _clearRoutePolyline(), // Clear on map tap
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.busflow.app',
              ),

              // Route Polyline Layer
              if (_selectedRoutePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _selectedRoutePoints,
                      color: Colors.blueAccent,
                      strokeWidth: 4.0,
                    ),
                  ],
                ),

              // Bus Stops Layer
              busStopsAsync.when(
                data: (stops) => MarkerLayer(
                  markers: stops
                      .map(
                        (stop) => Marker(
                          point: LatLng(stop.latitude, stop.longitude),
                          width: 24,
                          height: 24,
                          child: Tooltip(
                            message: '${stop.name}\n(Código: ${stop.code})',
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(
                                  color: Colors.blueAccent,
                                  width: 2,
                                ),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.local_parking,
                                size: 14,
                                color: Colors.blueAccent,
                              ),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
                loading: () => const MarkerLayer(markers: []),
                error: (_, _) => const MarkerLayer(markers: []),
              ),

              // User Location Marker
              userLocationAsync.when(
                data: (pos) => MarkerLayer(
                  markers: [
                    Marker(
                      point: LatLng(pos.latitude, pos.longitude),
                      width: 40,
                      height: 40,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.3),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue, width: 2),
                        ),
                        child: const Icon(
                          Icons.my_location,
                          color: Colors.blue,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
                loading: () => const MarkerLayer(markers: []),
                error: (_, _) => const MarkerLayer(markers: []),
              ),

              // Vehicle Clustering Layer
              vehiclePositionsAsync.when(
                data: (positions) => MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 120,
                    size: const Size(40, 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(50),
                    maxZoom: 15,
                    markers: positions
                        .map((pos) => _buildBusMarker(context, pos))
                        .toList(),
                    builder: (context, markers) {
                      return Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.blue,
                        ),
                        child: Center(
                          child: Text(
                            markers.length.toString(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                loading: () => const MarkerLayer(markers: []),
                error: (error, stack) => const MarkerLayer(markers: []),
              ),
            ],
          ),

          // Floating Search Bar
          Positioned(
            top: 50, // StatusBar margin
            left: 16,
            right: 16,
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar linha ou destino...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Favorites Filter Button
                      Consumer(
                        builder: (context, ref, _) {
                          final showFavorites = ref.watch(
                            showFavoritesProvider,
                          );
                          return IconButton(
                            icon: Icon(
                              showFavorites ? Icons.star : Icons.star_border,
                              color: showFavorites ? Colors.amber : Colors.grey,
                            ),
                            onPressed: () {
                              ref.read(showFavoritesProvider.notifier).state =
                                  !showFavorites;
                            },
                            tooltip: 'Mostrar favoritos',
                          );
                        },
                      ),
                      // Clear Search Button
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.grey),
                        onPressed: () {
                          ref.read(searchControllerProvider).add('');
                        },
                      ),
                    ],
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 15,
                  ),
                ),
                onChanged: (value) {
                  ref.read(searchControllerProvider).add(value);
                },
              ),
            ),
          ),

          // Geolocation Button (FAB)
          Positioned(
            bottom: 30,
            right: 16,
            child: FloatingActionButton(
              onPressed: () async {
                final geoService = ref.read(geoLocatorProvider);
                try {
                  final pos = await geoService.getCurrentPosition();
                  _mapController.move(
                    LatLng(pos.latitude, pos.longitude),
                    16.0,
                  );
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Erro ao obter localização.'),
                      ),
                    );
                  }
                }
              },
              backgroundColor: Colors.white,
              child: const Icon(Icons.my_location, color: Colors.blue),
            ),
          ),

          // Loading Indicator
          if (vehiclePositionsAsync.isLoading)
            const Positioned(
              top: 110,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Marker _buildBusMarker(BuildContext context, VehiclePosition pos) {
    return Marker(
      point: LatLng(pos.latitude, pos.longitude),
      width: 40,
      height: 40,
      child: GestureDetector(
        onTap: () {
          _showRoutePolyline(pos);
          setState(() {
            _trackedBusId = pos.tripId;
          });

          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Rastreando chegada deste ônibus... 🔔'),
              ),
            );
          }

          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (ctx) => BusDetailSheet(
              vehicle: pos,
              onReport: (issueType) {
                // Close sheet
                Navigator.pop(ctx);

                // Show confirmation
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Reportado: $issueType para ${pos.tripId}'),
                    backgroundColor: Colors.orange,
                  ),
                );

                // Log to console (Mock backend integration)
                // debugPrint('⚠️ REPORT: $issueType on Bus ${pos.tripId}');
              },
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: pos.source == 'api_public' ? Colors.blue : Colors.green,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(
            Icons.directions_bus,
            color: Colors.white,
            size: 20,
          ),
        ),
      ),
    );
  }
}
