import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:pactaflow/core/config/constants.dart';
import 'package:pactaflow/core/theme/app_theme.dart';
import 'package:pactaflow/state/providers/fleet_providers.dart';
import 'package:pactaflow/application/projections/providers/fleet_status_projection_provider.dart';
import 'package:pactaflow/application/projections/providers/command_center_filter_provider.dart';
import 'package:pactaflow/application/projections/providers/fleet_attention_projection_provider.dart';
import 'package:pactaflow/dev/performance_metrics.dart';
import '../map_widgets/animated_vehicle_marker.dart';

/// The main fleet map for the Command Center.
///
/// Displays all active vehicles as colored markers on a dark map,
/// centered on São Paulo. Supports vehicle selection and map interaction.
class FleetMap extends ConsumerStatefulWidget {
  const FleetMap({super.key});

  @override
  ConsumerState<FleetMap> createState() => _FleetMapState();
}

class _FleetMapState extends ConsumerState<FleetMap> {
  final MapController _mapController = MapController();
  bool _showLabels = true;

  @override
  Widget build(BuildContext context) {
    final positionsAsync = ref.watch(normalizedStateProvider);
    final projection = ref.watch(fleetStatusProjectionProvider);
    final tripsAsync = ref.watch(tripStreamProvider);
    final selectedId = ref.watch(selectedTripIdProvider);

    // Follow Mode: Pan map when new coordinates arrive for the tracked vehicle
    ref.listen(normalizedStateProvider, (previous, next) {
      final filter = ref.read(commandCenterFilterProvider);
      if (filter.followVehicleId != null && next.hasValue) {
        final vehicle = next.value!
            .where((v) => v.vehicleId == filter.followVehicleId)
            .firstOrNull;
        if (vehicle != null) {
          _mapController.move(
            LatLng(vehicle.latitude, vehicle.longitude),
            _mapController.camera.zoom,
          );
        }
      }
    });

    // Follow Mode: Initial jump when a new vehicle is selected to follow
    ref.listen(commandCenterFilterProvider, (previous, next) {
      if (next.followVehicleId != null &&
          previous?.followVehicleId != next.followVehicleId) {
        final positions = ref.read(normalizedStateProvider).valueOrNull;
        final vehicle = positions
            ?.where((v) => v.vehicleId == next.followVehicleId)
            .firstOrNull;
        if (vehicle != null) {
          final targetZoom = _mapController.camera.zoom < 15.0
              ? 16.0
              : _mapController.camera.zoom;
          _mapController.move(
            LatLng(vehicle.latitude, vehicle.longitude),
            targetZoom,
          );
        }
      }
    });

    return Stack(
      children: [
        // ── Base Map ───────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(
              AppConstants.defaultLatitude,
              AppConstants.defaultLongitude,
            ),
            initialZoom: AppConstants.defaultZoom,
            minZoom: 10,
            maxZoom: 18,
            backgroundColor: PactaFlowColors.background,
            onPositionChanged: (position, hasGesture) {
              final zoom = position.zoom;
              final shouldShowLabels = zoom >= 14.0;
              if (_showLabels != shouldShowLabels) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _showLabels = shouldShowLabels);
                });
              }

              if (hasGesture) {
                // Break follow mode if operator manually pans the map
                final filter = ref.read(commandCenterFilterProvider);
                if (filter.followVehicleId != null) {
                  ref
                      .read(commandCenterFilterProvider.notifier)
                      .setFollowVehicleId(null);
                }
              }
            },
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            // Dark tile layer
            TileLayer(
              urlTemplate: _buildTileUrl(),
              userAgentPackageName: 'com.PactaFlow.admin',
              tileBuilder: _darkTileBuilder,
            ),

            // Animated Vehicle markers
            RebuildCounter(
              name: 'FleetMap',
              child: AnimatedFleetMarkerLayer(
                states: projection.allFilteredVehicles,
                trips: tripsAsync.valueOrNull ?? [],
                attentionProjection: ref.watch(
                  fleetAttentionProjectionProvider,
                ),
                selectedId: selectedId,
                showLabels: _showLabels,
                onMarkerTap: (tripId) {
                  ref.read(selectedTripIdProvider.notifier).state = tripId;

                  // Active Follow Mode
                  final vehicle = projection.allFilteredVehicles
                      .where((v) => v.tripId == tripId)
                      .firstOrNull;

                  if (vehicle != null) {
                    ref
                        .read(commandCenterFilterProvider.notifier)
                        .setFollowVehicleId(vehicle.vehicleId);

                    // Instant Pan
                    final targetZoom = _mapController.camera.zoom < 15.0
                        ? 16.0
                        : _mapController.camera.zoom;
                    _mapController.move(
                      LatLng(vehicle.latitude, vehicle.longitude),
                      targetZoom,
                    );
                  }
                },
              ),
            ),
          ],
        ),

        // ── Map Controls ───────────────────────────────
        Positioned(
          right: 12,
          bottom: 48,
          child: Column(
            children: [
              _MapControlButton(
                icon: Icons.add,
                onTap: () {
                  final currentZoom = _mapController.camera.zoom;
                  _mapController.move(
                    _mapController.camera.center,
                    currentZoom + 1,
                  );
                },
              ),
              const SizedBox(height: 4),
              _MapControlButton(
                icon: Icons.remove,
                onTap: () {
                  final currentZoom = _mapController.camera.zoom;
                  _mapController.move(
                    _mapController.camera.center,
                    currentZoom - 1,
                  );
                },
              ),
              const SizedBox(height: 8),
              _MapControlButton(
                icon: Icons.my_location,
                onTap: () {
                  _mapController.move(
                    const LatLng(
                      AppConstants.defaultLatitude,
                      AppConstants.defaultLongitude,
                    ),
                    AppConstants.defaultZoom,
                  );
                },
              ),
            ],
          ),
        ),

        // ── Loading indicator ──────────────────────────
        if (positionsAsync.isLoading)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: PactaFlowColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: PactaFlowColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('Carregando...', style: PactaFlowTypography.caption),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _buildTileUrl() {
    // Use MapTiler dark style if key is available, otherwise use OSM
    if (AppConstants.mapTilerKey != 'get_your_own_key') {
      return AppConstants.mapTileUrl.replaceAll(
        '{key}',
        AppConstants.mapTilerKey,
      );
    }
    // Fallback to OSM with dark CSS filter applied in _darkTileBuilder
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  /// Apply a dark filter to standard OSM tiles when MapTiler is unavailable.
  Widget _darkTileBuilder(
    BuildContext context,
    Widget tileWidget,
    TileImage tile,
  ) {
    // Web browsers enforce strict CORS policies that block Canvas reading (WebGL)
    // of cross-origin imagery. Avoid the ColorFilter on web to prevent canvas tainting.
    if (kIsWeb) return tileWidget;

    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        -0.8, 0.0, 0.0, 0.0, 40.0, //
        0.0, -0.8, 0.0, 0.0, 40.0, //
        0.0, 0.0, -0.8, 0.0, 50.0, //
        0.0, 0.0, 0.0, 1.0, 0.0, //
      ]),
      child: tileWidget,
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PactaFlowColors.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: PactaFlowColors.border),
          ),
          child: Icon(icon, size: 16, color: PactaFlowColors.textSecondary),
        ),
      ),
    );
  }
}
