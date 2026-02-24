import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/config/constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../state/providers/fleet_providers.dart';
import '../map_widgets/vehicle_marker.dart';

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

  @override
  Widget build(BuildContext context) {
    final positionsAsync = ref.watch(positionStreamProvider);
    final tripsAsync = ref.watch(tripStreamProvider);
    final selectedId = ref.watch(selectedTripIdProvider);

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
            backgroundColor: BusFlowColors.background,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            // Dark tile layer
            TileLayer(
              urlTemplate: _buildTileUrl(),
              userAgentPackageName: 'com.busflow.admin',
              tileBuilder: _darkTileBuilder,
            ),

            // Vehicle markers
            MarkerLayer(
              markers: _buildMarkers(positionsAsync, tripsAsync, selectedId),
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
                color: BusFlowColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: BusFlowColors.primary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('Carregando...', style: BusFlowTypography.caption),
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

  List<Marker> _buildMarkers(
    AsyncValue<List<dynamic>> positionsAsync,
    AsyncValue<List<dynamic>> tripsAsync,
    String? selectedId,
  ) {
    final positions = positionsAsync.valueOrNull ?? [];
    final trips = tripsAsync.valueOrNull ?? [];

    return positions.map<Marker>((pos) {
      // Find matching trip for this position
      final trip = trips
          .cast<dynamic>()
          .where((t) => t.id == pos.tripId)
          .firstOrNull;
      final status = trip?.status ?? _inferStatusFromPosition(pos);
      final routeLabel = pos.routeName ?? '?';
      final isSelected = pos.tripId == selectedId;

      return Marker(
        point: LatLng(pos.latitude, pos.longitude),
        width: 48,
        height: 40,
        child: VehicleMarkerWidget(
          status: status,
          routeLabel: routeLabel,
          heading: pos.heading,
          isSelected: isSelected,
          isStale: pos.isStale(),
          onTap: () {
            ref.read(selectedTripIdProvider.notifier).state = pos.tripId;
          },
        ),
      );
    }).toList();
  }

  dynamic _inferStatusFromPosition(dynamic pos) {
    // If we can't find a trip, infer from speed
    if (pos.speed != null && pos.speed < 2.0) {
      return _defaultStatus;
    }
    return _defaultStatus;
  }

  // ignore: unused_element
  static final _defaultStatus = _DefaultStatusHelper();
}

/// Fallback for when trip status is unknown
class _DefaultStatusHelper {
  Color get color => BusFlowColors.neutral;
  String get label => 'Desconhecido';
  IconData get icon => Icons.help_outline;
  bool get isActive => true;
  bool get requiresAttention => false;
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _MapControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: BusFlowColors.surface.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: BusFlowColors.border),
          ),
          child: Icon(icon, size: 16, color: BusFlowColors.textSecondary),
        ),
      ),
    );
  }
}
